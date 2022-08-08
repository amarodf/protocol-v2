
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "../src/interfaces/IAssimilator.sol";
import "../src/interfaces/IOracle.sol";
import "../src/interfaces/IERC20Detailed.sol";
import "../src/AssimilatorFactory.sol";
import "../src/CurveFactoryV2.sol";
import "../src/Curve.sol";
import "../src/Structs.sol";
import "../src/Router.sol";
import "../src/lib/ABDKMath64x64.sol";

import "./lib/MockUser.sol";
import "./lib/CheatCodes.sol";
import "./lib/Address.sol";
import "./lib/CurveParams.sol";
import "./utils/Utils.sol";

contract RouterTest is Test {
    using SafeMath for uint256;

    CheatCodes cheats = CheatCodes(HEVM_ADDRESS);
    Utils utils;

    MockUser multisig;
    MockUser[2] public users;

    IERC20Detailed usdc = IERC20Detailed(Mainnet.USDC);
    IERC20Detailed cadc = IERC20Detailed(Mainnet.CADC);
    IERC20Detailed xsgd = IERC20Detailed(Mainnet.XSGD);
    IERC20Detailed euroc = IERC20Detailed(Mainnet.EUROC);

    uint8 constant fxTokenCount = 3;

    IERC20Detailed[] public foreignStables = [
        cadc,
        xsgd, 
        euroc, 
        usdc
    ];

    IOracle usdcOracle = IOracle(Mainnet.CHAINLINK_USDC_USD);
    IOracle cadcOracle = IOracle(Mainnet.CHAINLINK_CAD_USD);
    IOracle xsgdOracle = IOracle(Mainnet.CHAINLINK_SGD_USD);
    IOracle eurocOracle = IOracle(Mainnet.CHAINLINK_EUR_USD);

    IOracle[] public foreignOracles = [
        cadcOracle,
        xsgdOracle,
        eurocOracle,
        usdcOracle
    ];

    int128 public protocolFee = 50;

    AssimilatorFactory assimilatorFactory;
    CurveFactoryV2 curveFactory;
    Router router;
    Curve[fxTokenCount] dfxCurves;

    function setUp() public {
        multisig = new MockUser();
        utils = new Utils();

        for (uint8 i = 0; i < users.length; i++) {
            users[i] = new MockUser();
        }

        assimilatorFactory = new AssimilatorFactory();
        
        curveFactory = new CurveFactoryV2(
            protocolFee,
            address(multisig),
            address(assimilatorFactory)
        );

        router = new Router(address(curveFactory));
        
        assimilatorFactory.setCurveFactory(address(curveFactory));
        
        for (uint8 i = 0; i < fxTokenCount; i++) {
            CurveInfo memory curveInfo = CurveInfo(
                string.concat("dfx-", foreignStables[i].symbol()),
                string.concat("dfx-", foreignStables[i].symbol()),
                address(foreignStables[i]),
                address(usdc),
                DefaultCurve.BASE_WEIGHT,
                DefaultCurve.QUOTE_WEIGHT,
                address(foreignOracles[i]),
                foreignStables[i].decimals(),
                address(usdcOracle),
                usdc.decimals()
            );

            dfxCurves[i] = curveFactory.newCurve(curveInfo);
            dfxCurves[i].setParams(
                DefaultCurve.ALPHA,
                DefaultCurve.BETA,
                DefaultCurve.MAX,
                DefaultCurve.EPSILON,
                DefaultCurve.LAMBDA
            );

            dfxCurves[i].turnOffWhitelisting();
        }
        

        uint256 user1TknAmnt = 300_000_000;

        // Mint Foreign Stables
        for (uint8 i = 0; i <= fxTokenCount; i++) {
            uint256 decimals = utils.tenToPowerOf(foreignStables[i].decimals());
            deal(address(foreignStables[i]), address(users[0]), user1TknAmnt.mul(decimals));
        }
        
        cheats.startPrank(address(users[0]));
        for (uint8 i = 0; i < fxTokenCount; i++) {            
            foreignStables[i].approve(address(dfxCurves[i]), type(uint).max);
            foreignStables[i].approve(address(router), type(uint).max);
            usdc.approve(address(dfxCurves[i]), type(uint).max);
        }
        usdc.approve(address(router), type(uint).max);
        cheats.stopPrank();

        cheats.startPrank(address(users[0]));
        for (uint8 i = 0; i < fxTokenCount; i++) {           
            dfxCurves[i].deposit(100_000_000e18, block.timestamp + 60);
        }
        cheats.stopPrank();
    }


    function routerOriginSwapAndCheck(
        IERC20Detailed fromToken, 
        IERC20Detailed toToken, 
        IOracle fromOracle, 
        IOracle toOracle, 
        uint256 _amount) public {
        
        uint8 fromDecimals = fromToken.decimals();
        uint8 toDecimals = toToken.decimals();

        uint256 amount = uint256(_amount).mul(fromDecimals);

        deal(address(fromToken), address(this), amount);
        fromToken.approve(address(router), type(uint).max);
            
        uint256 beforeAmount = toToken.balanceOf(address(this));
        
        router.originSwap(Mainnet.USDC, address(fromToken), address(toToken), amount, 0, block.timestamp + 60);
        
        uint256 afterAmount = toToken.balanceOf(address(this));

        // Get oracle rates assuming decimals are equal
        uint256 fromRate = uint256(fromOracle.latestAnswer());
        uint256 toRate = uint256(toOracle.latestAnswer());

        uint256 obtained = afterAmount.sub(beforeAmount);
        uint256 expected = amount.mul(fromRate).div(toRate);

        if (fromDecimals <= toDecimals) {
            uint8 decimalsDiff = toToken.decimals() - fromToken.decimals();
            expected = expected.mul(10 ** decimalsDiff);
        } else {
            uint8 decimalsDiff = fromToken.decimals() - toToken.decimals();
            expected = expected.div(10 ** decimalsDiff);
        }

        // 99.9% approximate
        assertApproxEqRel(obtained, expected, 0.999e18);
    }

    function testCadcToUsdcTargetSwap(uint256 _amount) public {
        cheats.assume(_amount > 10);
        cheats.assume(_amount < 10_000_000);

        routerOriginSwapAndCheck(cadc, usdc, cadcOracle, usdcOracle, _amount);
    }

    function testUsdcToXsgdTargetSwap(uint256 _amount) public {
        cheats.assume(_amount > 10);
        cheats.assume(_amount < 10_000_000);

        routerOriginSwapAndCheck(usdc, xsgd, usdcOracle, xsgdOracle, _amount);
    }

    function testCadcToEursTargetSwap(uint256 _amount) public {
        cheats.assume(_amount > 10);
        cheats.assume(_amount < 10_000_000);

        routerOriginSwapAndCheck(cadc, euroc, cadcOracle, eurocOracle, _amount);
    }

    function testCadcToXsgdTargetSwap(uint256 _amount) public {
        cheats.assume(_amount > 10);
        cheats.assume(_amount < 10_000_000);

        routerOriginSwapAndCheck(cadc, xsgd, cadcOracle, xsgdOracle, _amount);
    }

    function testEurocToXsgdTargetSwap(uint256 _amount) public {
        cheats.assume(_amount > 10);
        cheats.assume(_amount < 10_000_000);

        routerOriginSwapAndCheck(euroc, xsgd, eurocOracle, xsgdOracle, _amount);
    }

    function testEurocToCadcTargetSwap(uint256 _amount) public {
        cheats.assume(_amount > 10);
        cheats.assume(_amount < 10_000_000);

        routerOriginSwapAndCheck(euroc, cadc, eurocOracle, cadcOracle, _amount);
    }

    function testXSGDToEurocTargetSwap(uint256 _amount) public {
        cheats.assume(_amount > 10);
        cheats.assume(_amount < 10_000_000);

        routerOriginSwapAndCheck(xsgd, euroc, xsgdOracle, eurocOracle, _amount);
    }

    function testXSGDToCadcTargetSwap(uint256 _amount) public {
        cheats.assume(_amount > 10);
        cheats.assume(_amount < 10_000_000);

        routerOriginSwapAndCheck(xsgd, cadc, xsgdOracle, cadcOracle, _amount);
    }
}