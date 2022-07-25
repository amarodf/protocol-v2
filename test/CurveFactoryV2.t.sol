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
import "../src/lib/ABDKMath64x64.sol";

import "./lib/MockUser.sol";
import "./lib/CheatCodes.sol";
import "./lib/Address.sol";
import "./lib/CurveParams.sol";

import "./utils/Utils.sol";

contract CurveFactoryV2Test is Test {
    using SafeMath for uint256;

    uint256 public totalPercentage = 1e18;

    CheatCodes cheats = CheatCodes(HEVM_ADDRESS);
    Utils utils;
    MockUser treasury;

    MockUser[2] public users;

    IERC20Detailed usdc = IERC20Detailed(Mainnet.USDC);
    IERC20Detailed cadc = IERC20Detailed(Mainnet.CADC);
    IERC20Detailed xsgd = IERC20Detailed(Mainnet.XSGD);
    IERC20Detailed euroc = IERC20Detailed(Mainnet.EUROC);

    uint8 constant fxTokenCount = 3;
    // USDC always last so that the array does not clash
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
    Curve[fxTokenCount] dfxCurves;

    function setUp() public {
        treasury = new MockUser();
        utils = new Utils();

        for (uint8 i = 0; i < users.length; i++) {
            users[i] = new MockUser();
        }

        assimilatorFactory = new AssimilatorFactory();
        
        curveFactory = new CurveFactoryV2(
            protocolFee,
            address(treasury),
            address(assimilatorFactory)
        );
        
        assimilatorFactory.setCurveFactory(address(curveFactory));
        
        for (uint8 i = 0; i < fxTokenCount; i++) {
            CurveInfo memory curveInfo = CurveInfo(
                string.concat("dfx-", foreignStables[i].name()),
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

        // Mint Tokens for Mock Users
        uint256 user1TknAmnt = 300_000_000;
        uint256 user2TknAmnt = 0;

        // Mint Foreign Stables
        for (uint8 i = 0; i < foreignStables.length; i++) {
            uint256 decimals = utils.tenToPowerOf(foreignStables[i].decimals());
            deal(address(foreignStables[i]), address(users[0]), user1TknAmnt.mul(decimals));
            deal(address(foreignStables[i]), address(users[1]), user2TknAmnt.mul(decimals));
        }

        // Mint USDC
        deal(address(usdc), address(users[0]), user1TknAmnt.mul(utils.tenToPowerOf(usdc.decimals())));

        // Infinite Approvals
        for (uint8 i = 0; i < users.length; i++) {
            // Prentending to be a user
            cheats.startPrank(address(users[i]));
            for (uint8 j = 0; j < fxTokenCount; j++) {            
                foreignStables[j].approve(address(dfxCurves[j]), type(uint).max);
                usdc.approve(address(dfxCurves[j]), type(uint).max);
            }
            cheats.stopPrank();
        }
    }

    function testProtocolFee() public {

        cheats.prank(address(users[0]));
        dfxCurves[0].deposit(1_000_000e18, block.timestamp + 60);
        console.log(usdc.balanceOf(address(dfxCurves[0])));
        console.log(cadc.balanceOf(address(dfxCurves[0])));

        // send some cadc to users[1]
        deal(address(cadc),address(users[1]), 190_000e18);

        cheats.startPrank(address(users[1]));

        uint256 swapAmount = cadc.balanceOf(address(users[1]));

        // console.log(usdc.balanceOf(address(treasury)));
        dfxCurves[0].originSwap(Mainnet.CADC, Mainnet.USDC, swapAmount, 0, block.timestamp + 60);
        uint256 userUsdcBal = usdc.balanceOf(address(users[1]));
        uint256 treasuryUsdcBal = usdc.balanceOf(address(treasury));
        // console.log(swapAmount);
        // console.log(userUsdcBal);
        // console.log(treasuryUsdcBal);

        uint256 newSwapBalance = usdc.balanceOf(address(users[1]));
        console.log(newSwapBalance);
        dfxCurves[0].originSwap(Mainnet.USDC, Mainnet.CADC, newSwapBalance, 0, block.timestamp + 60);
        uint256 userCadcBal = cadc.balanceOf(address(users[1]));
        uint256 treasuryCadcBal = cadc.balanceOf(address(treasury));

        uint256 feeRatio = totalPercentage.div(DefaultCurve.EPSILON);
        uint256 balanceRatio = (userUsdcBal + treasuryUsdcBal).div(treasuryUsdcBal).div(2);
    }

    function testFailSwapDiff() public {
        
        cheats.prank(address(users[0]));
        dfxCurves[0].deposit(1_000_000e18, block.timestamp + 60);

        // send some cadc to users[1]
        deal(address(cadc),address(users[1]), 200_000e18);

        cheats.startPrank(address(users[1]));
        uint256 originalBal = cadc.balanceOf(address(users[1]));
        uint256 swapAmount = cadc.balanceOf(address(users[1]));
        dfxCurves[0].originSwap(Mainnet.CADC, Mainnet.USDC, swapAmount, 0, block.timestamp + 60);
        uint256 newSwapBalance = usdc.balanceOf(address(users[1]));
        dfxCurves[0].originSwap(Mainnet.USDC, Mainnet.CADC, newSwapBalance, 0, block.timestamp + 60);
        uint256 newlBal = cadc.balanceOf(address(users[1]));
        assertApproxEqAbs(originalBal, newlBal, originalBal.div(10000));
    }

    function testSwapDiff(uint256 mintAmount) public {
        cheats.assume(mintAmount > 1e18);
        cheats.assume(mintAmount < 200_000e18);
        cheats.prank(address(users[0]));
        dfxCurves[0].deposit(1_000_000e18, block.timestamp + 60);

        // send some cadc to users[1]
        deal(address(cadc),address(users[1]), mintAmount);

        cheats.startPrank(address(users[1]));
        uint256 originalBal = cadc.balanceOf(address(users[1]));
        uint256 swapAmount = cadc.balanceOf(address(users[1]));
        dfxCurves[0].originSwap(Mainnet.CADC, Mainnet.USDC, swapAmount, 0, block.timestamp + 60);
        uint256 newSwapBalance = usdc.balanceOf(address(users[1]));
        dfxCurves[0].originSwap(Mainnet.USDC, Mainnet.CADC, newSwapBalance, 0, block.timestamp + 60);
        uint256 newlBal = cadc.balanceOf(address(users[1]));
        assertApproxEqAbs(originalBal, newlBal, originalBal.div(1000));
    }
}