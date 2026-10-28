# ChainArena contracts — 常用命令
# 用法: make help / make test / make anvil-up / make deploy-local ...

RPC_LOCAL     := http://127.0.0.1:8545
ANVIL_KEY0    := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
ANVIL_KEY1    := 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
# 演示用 passkey 公钥（32B 零填充）
PKX           := 0x00000000000000000000000000000000000000000000000000000000009d3c01
PKY           := 0x0000000000000000000000000000000000000000000000000000000000f1a202

.PHONY: help build test fmt coverage anvil-up anvil-down \
        deploy-local demo-local deploy-base-sepolia

help:
	@echo "build              编译合约"
	@echo "test               全量测试"
	@echo "fmt                格式化"
	@echo "coverage           覆盖率"
	@echo "anvil-up           启动本地 anvil (后台, chainId 31337)"
	@echo "anvil-down         停止 anvil"
	@echo "deploy-local       部署实现+工厂到本地 anvil"
	@echo "demo-local         一键演示: 预计算地址 → 铸账户 → 幂等重放"
	@echo "deploy-base-sepolia 部署到 Base Sepolia (需 DEPLOYER_PRIVATE_KEY)"

build:
	forge build

test:
	forge test

fmt:
	forge fmt

coverage:
	forge coverage

anvil-up:
	@if curl -s -m 1 -X POST $(RPC_LOCAL) -H 'Content-Type: application/json' \
		-d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' | grep -q 0x7a69; then \
		echo "anvil 已在运行 ($(RPC_LOCAL))"; \
	else \
		nohup anvil --silent > /tmp/anvil.log 2>&1 & sleep 2; echo "anvil 已启动 ($(RPC_LOCAL))"; \
	fi
	@cast chain-id --rpc-url $(RPC_LOCAL)

anvil-down:
	@pkill -f anvil && echo "anvil 已停止" || echo "anvil 未在运行"

deploy-local: anvil-up
	DEPLOYER_PRIVATE_KEY=$(ANVIL_KEY0) forge script script/DeployAccounts.s.sol \
		--rpc-url $(RPC_LOCAL) \
		--broadcast

# 读取最新部署的 factory 地址（broadcast 产物；惰性求值，在 deploy 之后执行时才读取）
FACTORY = $(shell python3 -c "import json,glob;f=sorted(glob.glob('broadcast/DeployAccounts.s.sol/*/run-latest.json'))[-1];print([t for t in json.load(open(f))['transactions'] if t['contractName']=='AccountFactory'][0]['contractAddress'])" 2>/dev/null)

demo-local: anvil-up deploy-local
	@echo "== 工厂地址: $(FACTORY)"
	@echo "== ① 预计算地址（view 免费）:"
	@cast call $(FACTORY) "getAddress(bytes32,bytes32,uint256)(address)" $(PKX) $(PKY) 0 --rpc-url $(RPC_LOCAL)
	@echo "== ② 首次部署（key#1 模拟 Bundler）:"
	@cast send $(FACTORY) "createAccount(bytes32,bytes32,uint256)" $(PKX) $(PKY) 0 \
		--private-key $(ANVIL_KEY1) --rpc-url $(RPC_LOCAL) --json 2>/dev/null \
		| python3 -c "import json,sys;r=json.load(sys.stdin);print('   gasUsed:',int(r['gasUsed'],16))"
	@echo "== ③ 幂等重放（应明显更省 gas）:"
	@sleep 1
	@cast send $(FACTORY) "createAccount(bytes32,bytes32,uint256)" $(PKX) $(PKY) 0 \
		--private-key $(ANVIL_KEY1) --rpc-url $(RPC_LOCAL) --json 2>/dev/null \
		| python3 -c "import json,sys;r=json.load(sys.stdin);print('   gasUsed:',int(r['gasUsed'],16))"

deploy-base-sepolia:
	@test -n "$$DEPLOYER_PRIVATE_KEY" || (echo "缺少 DEPLOYER_PRIVATE_KEY"; exit 1)
	forge script script/DeployAccounts.s.sol \
		--rpc-url https://sepolia.base.org \
		--broadcast --verify \
		--private-key $$DEPLOYER_PRIVATE_KEY
