// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

contract EIP2537 {
    error PrecompileError(string message);

    mapping(address => bytes) private pendingInputs;

    function clearInput() public {
        delete pendingInputs[msg.sender];
    }

    function addInputChunk(bytes memory chunk) public {
        pendingInputs[msg.sender] = bytes.concat(pendingInputs[msg.sender], chunk);
    }

    function callPrecompile(address precompile, bytes memory input) internal returns (bytes memory) {
        (bool success, bytes memory returnData) = precompile.call(input);
        assembly {
            if iszero(success) {
                let size := returndatasize()
                returndatacopy(0, 0, size)
                revert(0, size)
            }
        }
        return returnData;
    }

    function bls12381G1Add(bytes memory input) public returns (bytes memory) {
        bytes memory finalInput;
        if (pendingInputs[msg.sender].length > 0) {
            finalInput = pendingInputs[msg.sender];
            delete pendingInputs[msg.sender];
        } else {
            finalInput = input;
        }
        return callPrecompile(address(0x0b), finalInput);
    }

    function bls12381G1MultiExp(bytes memory input) public returns (bytes memory) {
        bytes memory finalInput;
        if (pendingInputs[msg.sender].length > 0) {
            finalInput = pendingInputs[msg.sender];
            delete pendingInputs[msg.sender];
        } else {
            finalInput = input;
        }
        return callPrecompile(address(0x0c), finalInput);
    }

    function bls12381G2Add(bytes memory input) public returns (bytes memory) {
        bytes memory finalInput;
        if (pendingInputs[msg.sender].length > 0) {
            finalInput = pendingInputs[msg.sender];
            delete pendingInputs[msg.sender];
        } else {
            finalInput = input;
        }
        return callPrecompile(address(0x0d), finalInput);
    }

    function bls12381G2MultiExp(bytes memory input) public returns (bytes memory) {
        bytes memory finalInput;
        if (pendingInputs[msg.sender].length > 0) {
            finalInput = pendingInputs[msg.sender];
            delete pendingInputs[msg.sender];
        } else {
            finalInput = input;
        }
        return callPrecompile(address(0xe), finalInput);
    }

    function bls12381Pairing(bytes memory input) public returns (bytes memory) {
        bytes memory finalInput;
        if (pendingInputs[msg.sender].length > 0) {
            finalInput = pendingInputs[msg.sender];
            delete pendingInputs[msg.sender];
        } else {
            finalInput = input;
        }
        return callPrecompile(address(0xf), finalInput);
    }

    function bls12381MapG1(bytes memory input) public returns (bytes memory) {
        bytes memory finalInput;
        if (pendingInputs[msg.sender].length > 0) {
            finalInput = pendingInputs[msg.sender];
            delete pendingInputs[msg.sender];
        } else {
            finalInput = input;
        }
        return callPrecompile(address(0x10), finalInput);
    }

    function bls12381MapG2(bytes memory input) public returns (bytes memory) {
        bytes memory finalInput;
        if (pendingInputs[msg.sender].length > 0) {
            finalInput = pendingInputs[msg.sender];
            delete pendingInputs[msg.sender];
        } else {
            finalInput = input;
        }
        return callPrecompile(address(0x11), finalInput);
    }
}
