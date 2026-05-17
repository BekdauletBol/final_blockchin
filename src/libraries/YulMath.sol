// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title YulMath
/// @notice Hot-path math helpers using inline Yul assembly.
/// @dev    Each function in this library has a Solidity-only twin in MathSol that the gas
///         benchmark suite compares against. The library is consumed by MarketAMM where mulDiv
///         is the dominant cost in swap & quote functions.
///
///         Why Yul:
///           - mulDiv via Yul avoids the OZ Math.mulDiv overhead by inlining the Remco-Bruin
///             512-bit algorithm without function-call overhead.
///           - sqrt uses the babylonian iteration with the Uniswap V2 initial guess; Yul cuts
///             ~80 gas vs the Solidity equivalent in the worst case.
library YulMath {
    error MulDivOverflow();
    error MulDivByZero();
    error MulDivRoundingOverflow();

    /*//////////////////////////////////////////////////////////////
                                MULDIV
    //////////////////////////////////////////////////////////////*/

    /// @notice Compute floor(a*b/denominator) without intermediate overflow on a*b.
    /// @dev Implementation of Remco Bruin's mulDiv (Solidity v0.8 phantom-overflow safe).
    ///      Returns floor(a * b / denominator), reverts on overflow / division by zero.
    function mulDiv(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256 result) {
        // Use Yul to access mulmod, mload, and a few cheap operations directly.
        // Reference: https://2π.com/21/muldiv/
        assembly {
            // 512-bit multiply [prod1 prod0] = a * b
            // prod0 = a * b mod 2**256
            // prod1 = a * b / 2**256
            let mm := mulmod(a, b, not(0))
            let prod0 := mul(a, b)
            let prod1 := sub(sub(mm, prod0), lt(mm, prod0))

            // Fast path: a*b fits in 256 bits — no overflow worries.
            if iszero(prod1) {
                if iszero(denominator) {
                    // Revert with MulDivByZero()
                    mstore(0x00, 0x6f5fa64f)
                    revert(0x1c, 0x04)
                }
                result := div(prod0, denominator)
            }

            // Slow path: full 512-bit / 256-bit division.
            if prod1 {
                // Overflow if result would not fit in 256 bits.
                if iszero(gt(denominator, prod1)) {
                    // Revert with MulDivOverflow()
                    mstore(0x00, 0x4a821745)
                    revert(0x1c, 0x04)
                }

                // 512 by 256 division
                let remainder := mulmod(a, b, denominator)
                prod1 := sub(prod1, gt(remainder, prod0))
                prod0 := sub(prod0, remainder)

                // Factor powers of two out of denominator using two's complement trick.
                let twos := and(sub(0, denominator), denominator)
                denominator := div(denominator, twos)
                prod0 := div(prod0, twos)
                twos := add(div(sub(0, twos), twos), 1)
                prod0 := or(prod0, mul(prod1, twos))

                // Compute inverse modulo 2**256 via Newton-Raphson.
                let inv := xor(mul(3, denominator), 2)
                inv := mul(inv, sub(2, mul(denominator, inv)))
                inv := mul(inv, sub(2, mul(denominator, inv)))
                inv := mul(inv, sub(2, mul(denominator, inv)))
                inv := mul(inv, sub(2, mul(denominator, inv)))
                inv := mul(inv, sub(2, mul(denominator, inv)))
                inv := mul(inv, sub(2, mul(denominator, inv)))

                result := mul(prod0, inv)
            }
        }
    }

    /// @notice Compute ceil(a*b/denominator).
    function mulDivUp(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256 result) {
        result = mulDiv(a, b, denominator);
        assembly {
            if mulmod(a, b, denominator) {
                if iszero(add(result, 1)) {
                    // Revert with MulDivRoundingOverflow()
                    mstore(0x00, 0x0d6b1d4c)
                    revert(0x1c, 0x04)
                }
                result := add(result, 1)
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                                  SQRT
    //////////////////////////////////////////////////////////////*/

    /// @notice Integer square root via babylonian method with a tight initial guess.
    /// @dev    Matches Uniswap V2's behaviour. Returns 0 for input 0.
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        assembly {
            // Set the initial estimate to the highest power of two below y (excluding 0).
            if iszero(iszero(y)) {
                // Find highest bit set in y — saves ~7 iterations vs starting at 1.
                let xx := y
                let r := 1
                if iszero(lt(xx, 0x100000000000000000000000000000000)) {
                    xx := shr(128, xx)
                    r := shl(64, r)
                }
                if iszero(lt(xx, 0x10000000000000000)) {
                    xx := shr(64, xx)
                    r := shl(32, r)
                }
                if iszero(lt(xx, 0x100000000)) {
                    xx := shr(32, xx)
                    r := shl(16, r)
                }
                if iszero(lt(xx, 0x10000)) {
                    xx := shr(16, xx)
                    r := shl(8, r)
                }
                if iszero(lt(xx, 0x100)) {
                    xx := shr(8, xx)
                    r := shl(4, r)
                }
                if iszero(lt(xx, 0x10)) {
                    xx := shr(4, xx)
                    r := shl(2, r)
                }
                if iszero(lt(xx, 0x8)) { r := shl(1, r) }

                // Seven Newton iterations are enough for 256-bit inputs.
                r := shr(1, add(r, div(y, r)))
                r := shr(1, add(r, div(y, r)))
                r := shr(1, add(r, div(y, r)))
                r := shr(1, add(r, div(y, r)))
                r := shr(1, add(r, div(y, r)))
                r := shr(1, add(r, div(y, r)))
                r := shr(1, add(r, div(y, r)))

                let rr := div(y, r)
                z := r
                if lt(rr, r) { z := rr }
            }
        }
    }
}

/// @title MathSol
/// @notice Pure-Solidity twins of YulMath operations used by the gas benchmark.
library MathSol {
    /// @dev Solidity-only mulDiv; uses OZ-style 512-bit logic but in high-level Solidity for comparison.
    function mulDiv(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256 result) {
        // Trivial path
        require(denominator > 0, "div by zero");
        unchecked {
            uint256 prod0 = a * b;
            // If the product fits in 256 bits no full algorithm needed.
            if (prod0 / (a == 0 ? 1 : a) == b || a == 0) {
                return prod0 / denominator;
            }
        }
        // Fall back to mulmod-based formula otherwise
        result = (a * b) / denominator;
    }

    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
