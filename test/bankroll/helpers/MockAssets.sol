// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";

contract MockToken is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) { }

    function mint(address recipient, uint256 amount) external {
        _mint(recipient, amount);
    }
}

contract MockWeth is ERC20 {
    constructor() ERC20("Wrapped Ether", "WETH") { }

    receive() external payable {
        deposit();
    }

    function deposit() public payable {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external {
        _burn(msg.sender, amount);
        (bool sent,) = msg.sender.call{ value: amount }("");
        require(sent);
    }
}

contract MockFixedToken is ERC20 {
    constructor(string memory name_, string memory symbol_, uint256 supply_, address recipient_) ERC20(name_, symbol_) {
        _mint(recipient_, supply_);
    }
}

contract MockUERC20Factory {
    error AddressMismatch(address actual, address predicted);

    function getUERC20Address(
        string calldata name,
        string calldata symbol,
        uint8 decimals,
        address recipient,
        bytes32 graffiti
    ) external view returns (address) {
        bytes32 salt = keccak256(abi.encode(name, symbol, decimals, recipient, graffiti));
        bytes memory code = abi.encodePacked(
            type(MockFixedToken).creationCode, abi.encode(name, symbol, uint256(1_000_000_000 ether), recipient)
        );
        return Create2.computeAddress(salt, keccak256(code));
    }

    function createToken(
        string calldata name,
        string calldata symbol,
        uint8 decimals,
        uint256 supply,
        address recipient,
        bytes calldata,
        bytes32 graffiti
    ) external returns (address token) {
        bytes32 salt = keccak256(abi.encode(name, symbol, decimals, recipient, graffiti));
        bytes memory code =
            abi.encodePacked(type(MockFixedToken).creationCode, abi.encode(name, symbol, supply, recipient));
        address predicted = Create2.computeAddress(salt, keccak256(code));
        token = address(new MockFixedToken{ salt: salt }(name, symbol, supply, recipient));
        if (token != predicted) revert AddressMismatch(token, predicted);
    }
}
