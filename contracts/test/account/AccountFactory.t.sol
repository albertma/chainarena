// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test, Vm } from "forge-std/Test.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ERC1967Utils } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { ISmartAccount } from "../../src/interfaces/ISmartAccount.sol";
import { SmartAccount } from "../../src/account/SmartAccount.sol";
import { AccountFactory } from "../../src/account/AccountFactory.sol";

/// @title AccountFactory 测试——P1-A 验收（docs/tech/01-signup.md §10 测试矩阵）
contract AccountFactoryTest is Test {
    SmartAccount internal implementation;
    AccountFactory internal factory;

    // 固定测试密钥（任意 32B，模拟 secp256r1 公钥坐标）
    bytes32 internal constant PKX = bytes32(uint256(0x9d3c01));
    bytes32 internal constant PKY = bytes32(uint256(0xf1a202));
    uint256 internal constant USER_SALT = 0;

    bytes32 internal constant ACCOUNT_CREATED_TOPIC0 =
        keccak256("AccountCreated(address,bytes32,uint256)");

    function setUp() public {
        implementation = new SmartAccount();
        factory = new AccountFactory(implementation);
    }

    // ------------------------------------------------------------------
    // ① 地址确定性
    // ------------------------------------------------------------------

    function test_GetAddress_IsDeterministic() public view {
        assertEq(factory.getAddress(PKX, PKY, USER_SALT), factory.getAddress(PKX, PKY, USER_SALT));
    }

    function test_GetAddress_DistinctForDifferentInputs() public view {
        assertTrue(
            factory.getAddress(PKX, PKY, 0) != factory.getAddress(bytes32(uint256(2)), PKY, 0),
            "x differs"
        );
        assertTrue(
            factory.getAddress(PKX, PKY, 0) != factory.getAddress(PKX, bytes32(uint256(3)), 0),
            "y differs"
        );
        // 同密钥换 userSalt = 换地址（高级设置：主动弃址）
        assertTrue(
            factory.getAddress(PKX, PKY, 0) != factory.getAddress(PKX, PKY, 1), "userSalt differs"
        );
    }

    /// 客户端镜像公式一致性：addr = keccak(0xff ‖ factory ‖ salt ‖ keccak(initCode))[12:]
    function test_GetAddress_MatchesClientMirrorFormula() public view {
        bytes memory initCode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(
                address(implementation), abi.encodeCall(ISmartAccount.initialize, (PKX, PKY))
            )
        );
        bytes32 create2Salt = bytes32(factory.computeSalt(PKX, PKY, USER_SALT));
        bytes32 hash = keccak256(
            abi.encodePacked(bytes1(0xff), address(factory), create2Salt, keccak256(initCode))
        );
        address expected = address(uint160(uint256(hash)));

        assertEq(factory.getAddress(PKX, PKY, USER_SALT), expected);
    }

    function test_ComputeSalt_MatchesDocsFormula() public view {
        assertEq(
            factory.computeSalt(PKX, PKY, USER_SALT),
            uint256(keccak256(abi.encodePacked(PKX, PKY, USER_SALT)))
        );
    }

    // ------------------------------------------------------------------
    // ② 部署与初始化
    // ------------------------------------------------------------------

    function test_CreateAccount_DeploysAndEmits() public {
        address predicted = factory.getAddress(PKX, PKY, USER_SALT);

        vm.expectEmit(true, true, true, true, address(factory));
        emit AccountFactory.AccountCreated(
            predicted, keccak256(abi.encodePacked(PKX, PKY)), USER_SALT
        );

        address deployed = factory.createAccount(PKX, PKY, USER_SALT);

        assertEq(deployed, predicted, "deployed address must equal prediction");
        assertTrue(deployed.code.length > 0, "account must have code");
    }

    function test_CreateAccount_ReturnsPredictedAddress() public {
        assertEq(
            factory.createAccount(PKX, PKY, USER_SALT), factory.getAddress(PKX, PKY, USER_SALT)
        );
    }

    /// 代理正确指向冻结实现（ERC-1967 implementation slot）
    function test_CreateAccount_ProxyPointsToFrozenImplementation() public {
        address account = factory.createAccount(PKX, PKY, USER_SALT);
        bytes32 implSlot = vm.load(account, ERC1967Utils.IMPLEMENTATION_SLOT);
        assertEq(address(uint160(uint256(implSlot))), address(implementation));
    }

    /// initialize 已执行：公钥落存储（后续 WebAuthnValidator 验签的注册源）
    function test_CreateAccount_InitializesOwnerPublicKey() public {
        SmartAccount account = SmartAccount(payable(factory.createAccount(PKX, PKY, USER_SALT)));
        assertEq(account.pubKeyX(), PKX);
        assertEq(account.pubKeyY(), PKY);
    }

    /// 实现合约自身禁初始化（不可被抢跑部署成「别人的账户」）
    function test_Implementation_DisallowsDirectInitialize() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(PKX, PKY);
    }

    /// 多玩家互不冲突：不同密钥各自铸账户；同密钥重放幂等返回同一地址
    function test_CreateAccount_MultiplePlayersNoCollision() public {
        for (uint256 i = 1; i <= 10; i++) {
            address a = factory.createAccount(bytes32(i), bytes32(i * 2), 0);
            assertTrue(a.code.length > 0);
        }
        address again = factory.createAccount(bytes32(uint256(1)), bytes32(uint256(2)), 0);
        assertEq(again, factory.getAddress(bytes32(uint256(1)), bytes32(uint256(2)), 0));
    }

    // ------------------------------------------------------------------
    // ③ 幂等与 EntryPoint initCode 语义
    // ------------------------------------------------------------------

    /// 调用者无关性：EntryPoint（或任何人）调 createAccount，地址与客户端预计算恒等
    /// （CREATE2 地址只由 factory+salt+initCode 决定，与 msg.sender 无关）
    function test_CreateAccount_CallerIndependent() public {
        address expected = factory.getAddress(PKX, PKY, USER_SALT);

        vm.prank(address(0xA11CE));
        address byAlice = factory.createAccount(PKX, PKY, USER_SALT);
        assertEq(byAlice, expected, "alice's deployment must match prediction");

        vm.prank(address(0xB0B));
        address byBob = factory.createAccount(PKX, PKY, USER_SALT); // 幂等路径
        assertEq(byBob, expected, "bob's replay must return same account");
    }

    /// 账户自身守卫：经代理再次 initialize 必须 revert（防止恶意改写 owner 公钥）
    function test_Proxy_DisallowsReinitialize() public {
        SmartAccount account = SmartAccount(payable(factory.createAccount(PKX, PKY, USER_SALT)));

        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        account.initialize(bytes32(uint256(0xdead)), bytes32(uint256(0xbeef)));

        // 原公钥未被篡改
        assertEq(account.pubKeyX(), PKX);
        assertEq(account.pubKeyY(), PKY);
    }

    /// 中断续跑根基：同参数再次 createAccount → 同地址、不 revert、不重复发事件
    function test_CreateAccount_IsIdempotent_NoDuplicateEvent() public {
        address first = factory.createAccount(PKX, PKY, USER_SALT);
        uint256 codeSizeBefore = first.code.length;

        vm.recordLogs();
        address second = factory.createAccount(PKX, PKY, USER_SALT);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(first, second, "same keys+salt must return same account");
        assertEq(second.code.length, codeSizeBefore, "no redeployment");

        uint256 createdEvents;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter == address(factory) && logs[i].topics[0] == ACCOUNT_CREATED_TOPIC0)
            {
                ++createdEvents;
            }
        }
        assertEq(createdEvents, 0, "idempotent call must not emit AccountCreated again");
    }

    /// EntryPoint 视角的 initCode 路径：initCode = factory 地址(20B) ‖ createAccount calldata，
    /// EntryPoint 拆出目标后发起 CALL（模拟同语义）
    function test_EntryPointStyle_InitCodePath() public {
        bytes memory callData = abi.encodeCall(AccountFactory.createAccount, (PKX, PKY, USER_SALT));
        bytes memory initCode = abi.encodePacked(address(factory), callData);

        address target = address(bytes20(initCode));
        assertEq(target, address(factory), "target must be factory");

        (bool ok, bytes memory ret) = target.call(callData);
        assertTrue(ok, "initCode execution must succeed");
        address account = abi.decode(ret, (address));
        assertEq(account, factory.getAddress(PKX, PKY, USER_SALT));
    }

    // ------------------------------------------------------------------
    // ④ Fuzz：任意密钥/盐组合的确定性
    // ------------------------------------------------------------------

    function testFuzz_GetAddress_AlwaysMatchesDeployment(bytes32 pkx, bytes32 pky, uint192 userSalt)
        public
    {
        address predicted = factory.getAddress(pkx, pky, userSalt);
        address deployed = factory.createAccount(pkx, pky, userSalt);
        assertEq(deployed, predicted);
        assertTrue(deployed.code.length > 0);
    }
}
