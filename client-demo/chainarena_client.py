#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ChainArena 客户端模拟器 —— 复现 docs/tech/01-signup.md 的客户端职责（@arena/core 的 Python 演示版）

按 P1 建号流程逐步执行：
  ① passkey 生成/恢复（cryptography 生成真 secp256r1 密钥对；真实产品由浏览器 WebAuthn + 安全芯片承担）
  ② CREATE2 地址本地预计算（零 RPC——与合约 getAddress 公式严格镜像）
  ③ 链上对账（factory.getAddress == 本地结果）
  ④ 重复注册预检（eth_getCode）
  ⑤ 发 UserOp 演化：createAccount 交易（funded key 模拟 Bundler 赞助通道）
  ⑥ 验证：账户代码 + pubKeyX/Y 经 delegatecall 可读
  ⑦ 幂等重放（同地址短路返回，gas 骤降）

用法：
  python3 chainarena_client.py                     # 全流程（密钥存 keys/passkey.json，重跑=中断续跑演示）
  python3 chainarena_client.py --fresh             # 新密钥（= 换 passkey，地址必变）
  python3 chainarena_client.py --no-deploy         # 只做 ①-④（纯只读）
"""

import argparse
import json
import sys
from pathlib import Path

from cryptography.hazmat.primitives.asymmetric import ec
from web3 import Web3

ROOT = Path(__file__).resolve().parent.parent
CONTRACTS = ROOT / "contracts"
HERE = Path(__file__).resolve().parent
KEYS_DIR = HERE / "keys"

# ---- 常量（与 docs/tech/01-signup.md §2.1 一致） ----------------------------
ANVIL_KEY1 = "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"  # 模拟 Bundler
INITIALIZE_SELECTOR = Web3.keccak(text="initialize(bytes32,bytes32)")[:4]

FACTORY_ABI = [
    {
        "name": "getAddress",
        "type": "function",
        "stateMutability": "view",
        "inputs": [
            {"name": "pubKeyX", "type": "bytes32"},
            {"name": "pubKeyY", "type": "bytes32"},
            {"name": "userSalt", "type": "uint256"},
        ],
        "outputs": [{"name": "", "type": "address"}],
    },
    {
        "name": "createAccount",
        "type": "function",
        "stateMutability": "nonpayable",
        "inputs": [
            {"name": "pubKeyX", "type": "bytes32"},
            {"name": "pubKeyY", "type": "bytes32"},
            {"name": "userSalt", "type": "uint256"},
        ],
        "outputs": [{"name": "", "type": "address"}],
    },
]

ACCOUNT_ABI = [
    {"name": "pubKeyX", "type": "function", "stateMutability": "view", "inputs": [], "outputs": [{"name": "", "type": "bytes32"}]},
    {"name": "pubKeyY", "type": "function", "stateMutability": "view", "inputs": [], "outputs": [{"name": "", "type": "bytes32"}]},
]

# ---- 工具 ------------------------------------------------------------------

step_no = 0


def step(title: str) -> None:
    global step_no
    step_no += 1
    print(f"\n[{step_no}] {title}")


def info(msg: str) -> None:
    print(f"    {msg}")


def die(msg: str) -> None:
    print(f"\n✗ {msg}", file=sys.stderr)
    sys.exit(1)


def load_proxy_creation_code() -> bytes:
    """ERC1967Proxy 创建字节码（编译产物；initCode 的第一段）"""
    art = CONTRACTS / "out" / "ERC1967Proxy.sol" / "ERC1967Proxy.json"
    if not art.exists():
        die(f"未找到编译产物 {art}，请先在 contracts/ 目录 forge build")
    obj = json.loads(art.read_text())["bytecode"]["object"]
    return bytes.fromhex(obj.removeprefix("0x"))


def find_latest_deploy():
    """从 forge broadcast 产物读取最近一次部署的 factory / impl 地址"""
    bdir = CONTRACTS / "broadcast" / "DeployAccounts.s.sol"
    runs = sorted(bdir.glob("*/run-latest.json"))
    if not runs:
        die("未找到部署记录（contracts/broadcast/...），请先 make deploy-local")
    txs = json.loads(runs[-1].read_text())["transactions"]
    out = {}
    for t in txs:
        if t.get("contractName") in ("AccountFactory", "SmartAccount"):
            out[t["contractName"]] = Web3.to_checksum_address(t["contractAddress"])
    return out.get("AccountFactory"), out.get("SmartAccount")


# ---- ① passkey（模拟） ------------------------------------------------------

def generate_passkey() -> tuple[bytes, bytes]:
    """生成真 secp256r1(P-256) 密钥对，导出公钥坐标 (x, y)

    与真实 WebAuthn 的差异：不经 Secure Enclave、无 RP ID 绑定、无计数器——
    P1-B 之前只用到「公钥进 CREATE2 盐」这一性质，演示足够。
    """
    priv = ec.generate_private_key(ec.SECP256R1())
    nums = priv.public_key().public_numbers()
    return nums.x.to_bytes(32, "big"), nums.y.to_bytes(32, "big")


def load_or_create_keyfile(path: Path, fresh: bool) -> tuple[bytes, bytes]:
    if path.exists() and not fresh:
        d = json.loads(path.read_text())
        info(f"恢复已有 passkey：{path}（中断续跑 / 重装恢复 同理）")
        return bytes.fromhex(d["x"]), bytes.fromhex(d["y"])
    x, y = generate_passkey()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"x": x.hex(), "y": y.hex(), "curve": "secp256r1"}, indent=2))
    info(f"新生成 passkey → {path}")
    info(f"    pubKeyX = 0x{x.hex()}")
    info(f"    pubKeyY = 0x{y.hex()}")
    return x, y


# ---- ② CREATE2 本地预计算（零 RPC，公式与 AccountFactory 严格镜像） ----------

def abi_encode_address_bytes(addr: str, data: bytes) -> bytes:
    """abi.encode(address, bytes) —— ERC1967Proxy 构造参数的手工编码"""
    head = bytes.fromhex(addr[2:].lower().rjust(64, "0"))  # address 左填充
    offset = (0x40).to_bytes(32, "big")                    # bytes 的偏移 = 0x40
    length = len(data).to_bytes(32, "big")
    padded = data + b"\x00" * ((32 - len(data) % 32) % 32)
    return head + offset + length + padded


def compute_address_local(factory: str, impl: str, x: bytes, y: bytes, user_salt: int) -> str:
    init_data = INITIALIZE_SELECTOR + x + y                            # initialize(x,y) calldata
    init_code = load_proxy_creation_code() + abi_encode_address_bytes(impl, init_data)
    salt = Web3.keccak(x + y + user_salt.to_bytes(32, "big"))           # keccak(x‖y‖userSalt)
    addr_hash = Web3.keccak(b"\xff" + bytes.fromhex(factory[2:]) + salt + Web3.keccak(init_code))
    return Web3.to_checksum_address(addr_hash[12:])


# ---- ③-⑦ 链上交互 -----------------------------------------------------------

def send_tx(w3: Web3, funded_key: str, to: str, data: bytes) -> dict:
    acct = w3.eth.account.from_key(funded_key)
    tx = {
        "to": Web3.to_checksum_address(to),
        "data": data,
        "gas": 600_000,
        "gasPrice": w3.eth.gas_price,
        "nonce": w3.eth.get_transaction_count(acct.address),
        "chainId": w3.eth.chain_id,
    }
    signed = acct.sign_transaction(tx)
    raw = getattr(signed, "raw_transaction", None) or signed.rawTransaction
    tx_hash = w3.eth.send_raw_transaction(raw)
    receipt = w3.eth.wait_for_transaction_receipt(tx_hash)
    if receipt["status"] != 1:
        die(f"交易失败: {tx_hash.hex()}")
    return receipt


def main() -> None:
    ap = argparse.ArgumentParser(description="ChainArena signup 客户端模拟器")
    ap.add_argument("--rpc", default="http://127.0.0.1:8545")
    ap.add_argument("--factory", help="工厂地址（默认读最新 broadcast）")
    ap.add_argument("--impl", help="实现地址（默认读最新 broadcast）")
    ap.add_argument("--keyfile", default=str(KEYS_DIR / "passkey.json"))
    ap.add_argument("--fresh", action="store_true", help="丢弃旧密钥，生成新 passkey")
    ap.add_argument("--user-salt", type=int, default=0)
    ap.add_argument("--no-deploy", action="store_true", help="只读模式：①-④ 不上链")
    ap.add_argument("--funded-key", default=ANVIL_KEY1, help="代发 gas 的 key（模拟 Bundler）")
    args = ap.parse_args()

    factory, impl = (args.factory, args.impl) if args.factory else find_latest_deploy()
    info(f"factory = {factory}")
    info(f"impl    = {impl}")

    # ① passkey
    step("passkey 生成/恢复（secp256r1）")
    x, y = load_or_create_keyfile(Path(args.keyfile), args.fresh)

    # ② 本地预计算（零 RPC）
    step("CREATE2 地址本地预计算（纯哈希，零 RPC）")
    local_addr = compute_address_local(factory, impl, x, y, args.user_salt)
    info(f"addr = {local_addr}")

    # ③ 链上对账
    step("链上对账：factory.getAddress == 本地公式")
    w3 = Web3(Web3.HTTPProvider(args.rpc))
    if not w3.is_connected():
        die(f"无法连接 RPC {args.rpc}（先 make anvil-up）")
    fac = w3.eth.contract(address=Web3.to_checksum_address(factory), abi=FACTORY_ABI)
    onchain_addr = fac.functions.getAddress(x, y, args.user_salt).call()
    info(f"链上  = {onchain_addr}")
    assert onchain_addr == local_addr, "客户端镜像公式与合约不一致！"
    info("✓ 逐字节一致（test_GetAddress_MatchesClientMirrorFormula 的运行时版本）")

    # ④ 重复注册预检
    step("重复注册预检 eth_getCode")
    code = w3.eth.get_code(local_addr)
    already = code != b""
    info("已注册（地址已有代码）" if already else "未注册 → 可部署")

    if args.no_deploy:
        print("\n--no-deploy：到此为止。同密钥重跑本脚本 → 地址不变（中断续跑根基）")
        return

    # ⑤ 部署（funded key 模拟 Bundler 赞助；真实版由 UserOp.initCode 经 EntryPoint 原子执行）
    step("createAccount 上链（模拟 Bundler 代发）" + (" —— 本次已是幂等路径" if already else ""))
    calldata = fac.encode_abi("createAccount", args=(x, y, args.user_salt))
    r1 = send_tx(w3, args.funded_key, factory, calldata)
    info(f"tx = {r1['transactionHash'].hex()}")
    info(f"gasUsed = {r1['gasUsed']:,}" + ("  ← 短路返回，未重新部署" if already else ""))

    # ⑥ 验证
    step("验证：账户代码 + 公钥经 delegatecall 可读")
    assert w3.eth.get_code(local_addr) != b""
    acc = w3.eth.contract(address=local_addr, abi=ACCOUNT_ABI)
    assert acc.functions.pubKeyX().call() == x, "pubKeyX 不匹配"
    assert acc.functions.pubKeyY().call() == y, "pubKeyY 不匹配"
    info(f"✓ {local_addr} 已部署，pubKeyX/Y == passkey 公钥")

    # ⑦ 幂等重放（仅首次部署时才做首次/重放 gas 对比）
    if already:
        info("地址与上一轮完全一致 —— 中断续跑/重装恢复的实证")
    else:
        step("幂等重放（同参数再发一笔）")
        r2 = send_tx(w3, args.funded_key, factory, calldata)
        info(f"gasUsed = {r2['gasUsed']:,}（首次 {r1['gasUsed']:,} → 短路返回）")
        assert r2["gasUsed"] < r1["gasUsed"] // 2

    print(f"\n✓ 全流程通过。你的 ChainArena 地址 = {local_addr}")
    print("  同一 keyfile 重跑 → 同一地址（重装/换机同理，passkey 云同步即可）")
    print("  --fresh 换新 passkey → 地址必变；--user-salt N → 同钥开小号")


if __name__ == "__main__":
    main()
