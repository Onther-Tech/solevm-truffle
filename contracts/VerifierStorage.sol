pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2;

import "./interfaces/IVerifierStorage.sol";
import "./HydratedRuntimeStorage.sol";
import "./MerkelizerStorage.slb";
import "./SMTVerifier.sol";
import './lib/RLPEncode.sol';
import './lib/RLPDecode.sol';
import './lib/SafeMath.sol';

contract VerifierStorage is IVerifierStorage, HydratedRuntimeStorage, SMTVerifier {
    using SafeMath for uint;

    using MerkelizerStorage for MerkelizerStorage.ExecutionState;
    using MerkelizerStorage for MerkelizerStorage.AccountProof;
    using MerkelizerStorage for MerkelizerStorage.Account;

    using RLPDecode for RLPDecode.RLPItem;
    using RLPDecode for bytes;
    using RLPEncode for *;

    // @dev for debug
    uint public val;
    uint public callerBalance;
    uint public calleeBalance;
    bytes public runtimeRlpVal;
    bytes public callerRlpVal;
    bytes public calleeRlpVal;
    bytes32 public callerBeforeLeaf;
    bytes32 public calleeBeforeLeaf;
    bytes32 public callerAfterLeaf;
    bytes32 public calleeAfterLeaf;
    bytes32 public inputHash;
    bytes32 public resultHash;
    bytes32 public callerKey;
    bytes32 public hashedKey;
    address public toAddress;
    bytes32 public accountHash;
    address public createdAddress;
    bytes32 public salt;

    struct MerkleProof {
        bytes32 callerKey;
        bytes32 calleeKey;
        bytes32 callerBeforeLeaf;
        bytes32 callerAfterLeaf;
        bytes32 calleeBeforeLeaf;
        bytes32 calleeAfterLeaf;
        bytes32 beforeRoot;
        bytes32 intermediateRoot;
        bytes32 afterRoot;
        bytes callerSiblings;
        bytes calleeSiblings;
    }

    struct Proofs {
        bytes32 stackHash;
        bytes32 memHash;
        bytes32 dataHash;
        uint256 codeByteLength;
        bytes32[] codeFragments;
        bytes32[] codeProof;
        bytes32 stateRoot;
        bytes32 storageRoot;
        bytes32 previousRuntimeStackHash;
        bytes32 runtimeStackHash;
        bytes32 accountHash;
        MerkelizerStorage.AccountProof storageAccount;
        MerkelizerStorage.AccountProof bytecodeAccount;
        bytes32 calleeCodeHash;
    }

    // @dev for solving stack too deep issue. 
    // it's useful to collect local variables in struct
    struct Hashes {
        bytes32 dataHash;
        bytes32 memHash;
        bytes32 codeHash;
        bytes32 tStorageHash;
        bytes32 inputHash;
        bytes32 resultHash;
        bytes32 callerHash;
        bytes32 calleeHash;
        bytes32 runtimeStackHash;
        bytes32 accountHash;
        uint value;
        bytes callerRlpVal;
        bytes calleeRlpVal;
        bytes32 callerBeforeLeaf;
        bytes32 calleeBeforeLeaf;
        bytes32 callerAfterLeaf;
        bytes32 calleeAfterLeaf;
        bool isValid;
        bool isStorageValid;
        uint8 opcode;
        uint stackSize;
        bytes32 beforeLeaf;
        bytes32 afterLeaf;
        bytes siblings;
        bytes32 saltForCREATE2;
        MerkelizerStorage.Account storageAccount;
    }

    /**
      * @dev Throw if not called by enforcer
      */
    modifier onlyEnforcer() {
        require(msg.sender == address(enforcer), "only enforcer");
        _;
    }

    /**
      * @dev game not timeout yet
      */
    modifier onlyPlaying(bytes32 disputeId) {
        Dispute storage dispute = disputes[disputeId];
        require(dispute.timeout >= block.timestamp, "game timed out");
        require((dispute.state & SOLVER_VERIFIED == 0) && (dispute.state & CHALLENGER_VERIFIED == 0), "dispute resolved");
        _;
    }

    /// @param timeout The time (in seconds) the participants have to react to `submitRound, submitProof`.
    /// 30 minutes is a good value for common use-cases.
    constructor(uint256 timeout) public {
        timeoutDuration = timeout;
    }

    // Due to the reverse dependency with Enforcer<>Verifier
    // we have to first deploy both contracts and peg it to one another.
    // Verifier gets deployed first, so Enforcer can be deployed with Verifier's
    // address in constructor, but Verifier itself needs to informed about Enforcer's address
    // after deployment. Checking if `enforcer` is `address(0)` here does the job.
    function setEnforcer(address _enforcer) public {
        require(address(enforcer) == address(0));

        enforcer = IEnforcerStorage(_enforcer);
    }

    /**
      * @dev init a new dispute, only callable by enforcer
      */
    function initGame(
        bytes32 executionId,
        bytes32 solverHashRoot,
        bytes32 challengerHashRoot,
        uint256 executionDepth,
         // optional for implementors
        // bytes32 customEnvironmentHash,
        // TODO: should be the bytes32 root hash later on
        bytes32 codeHash,
        bytes32 dataHash,
        bytes32 storageRoot,
        bytes32 stateRoot,
        bytes32 runtimeStackHash,
        bytes32 accountHash,
        address challenger
    ) public onlyEnforcer() returns (bytes32 disputeId) {
        bytes32 initialStateHash = MerkelizerStorage.initialStateHash(
            dataHash, storageRoot, stateRoot, runtimeStackHash, accountHash
        );

        disputeId = keccak256(
            abi.encodePacked(
                executionId,
                initialStateHash,
                solverHashRoot,
                challengerHashRoot,
                executionDepth
            )
        );

        require(disputes[disputeId].timeout == 0, "already init");
        // do we want to prohibit early?
        // require(solverHashRoot != challengerHashRoot, "nothing to challenge");

        disputes[disputeId] = Dispute(
            executionId,
            initialStateHash,
            codeHash,
            challenger,
            solverHashRoot,
            challengerHashRoot,
            executionDepth,
            bytes32(0),
            ComputationPath(solverHashRoot, solverHashRoot),
            ComputationPath(challengerHashRoot, challengerHashRoot),
            INITIAL_STATE,
            getTimeout()
        );
    }

    /*
     * Solver or Challenger always respond with the next `ComputationPath`
     * for the path they do not agree on.
     * If they do not agree on both `left` and `right` they must follow/default
     * to `left`.
     */
    function respond(
        bytes32 disputeId,
        ComputationPath memory computationPath,
        ComputationPath memory witnessPath
    ) public onlyPlaying(disputeId) {
        Dispute storage dispute = disputes[disputeId];

        require(dispute.treeDepth > 0, "already reach leaf");

        bytes32 h = keccak256(abi.encodePacked(computationPath.left, computationPath.right));

        require(
            h == dispute.solverPath || h == dispute.challengerPath,
            "wrong path submitted"
        );

        if (h == dispute.solverPath) {
            dispute.state |= SOLVER_RESPONDED;
            dispute.solver = computationPath;
        }

        if (h == dispute.challengerPath) {
            dispute.state |= CHALLENGER_RESPONDED;
            dispute.challenger = computationPath;
        }

        updateRound(disputeId, dispute, witnessPath);
    }

    function decodeAccount(
        MerkelizerStorage.AccountProof memory accountProof
    ) internal pure returns (MerkelizerStorage.Account memory a) {
        RLPDecode.RLPItem[] memory fields = accountProof.rlpVal.toRlpItem().toList();
        require(fields.length == 4, 'it shoud be length 4');
        a = MerkelizerStorage.Account(
            accountProof.addr,
            fields[0].toUint(), // nonce
            fields[1].toUint(), // balance
            fields[2].toBytes(), // codeHash
            fields[3].toBytes() // storageRoot
        );
    }

    // TODO: add complement in case of encoding zero in array
    // it evaluate different value on chain and off chain
    function encodeAccount (
        MerkelizerStorage.Account memory account
    ) internal pure returns (bytes memory out) {
        bytes[] memory packArr = new bytes[](4);
        packArr[0] = account.nonce.encodeUint();
        packArr[1] = account.balance.encodeUint();
        packArr[2] = account.codeHash.encodeBytes();
        packArr[3] = account.storageRoot.encodeBytes();
        
        return packArr.encodeList();
    }

    function generateAddressForCREATE (
        address addr,
        uint nonce
    ) internal pure returns (address) {
        bytes[] memory packArr = new bytes[](2);
        packArr[0] = addr.encodeAddress();
        packArr[1] = nonce.encodeUint();
        bytes memory rlpVal = packArr.encodeList();
        return address(uint160(uint256(keccak256(abi.encodePacked(rlpVal)))));
    }

    function generateAddressForCREATE2 (
        address addr,
        bytes32 salt,
        bytes32 codeHash
    ) internal pure returns (address) {
        address predictedAddress = address(uint(keccak256(abi.encodePacked(
            byte(0xff),
            addr,
            salt,
            codeHash
        ))));
        return predictedAddress;
    }

    /*
     * verify accounts of merkle proof in the case of CALLStart, CALLEnd, CALL with value, CREATE
     * CALL with value:
     *  - get rlp encodings of before step
     *  - rlp decode rlp encodings of before step
     *  - get value
     *  - calculate balances of caller account and callee account with value
     *  - rlp encode accounts
     *  - verify with merkle proof
     * CALLStart, CALLEnd:
     *  - check runtimeStackHash
     *  - verify with merkle proof
     * CREATE, CREATE2:
     *  - generate address based on whether CREATE or CREATE2
     *  - verify generated address
     *  - verify with merkle proof
     * Note: it is separated from submitProof due to stack too deep issue
     */
    // solhint-disable-next-line code-complexity
    function verifyAccount (
        Proofs memory proofs,
        MerkelizerStorage.ExecutionState memory executionState,
        MerkleProof memory merkleProof
    ) internal returns (bool) {
        Hashes memory hashes;
        hashes.isValid = false;
                   
        if (executionState.callValue) {
            // Question: we need to verify CREATE before transfer value?
            if (!executionState.isCREATE && !executionState.isCREATE2) {
                require(merkleProof.beforeRoot == proofs.stateRoot, 'they must be same state root ');
                require(merkleProof.afterRoot == executionState.stateRoot, 'they must be same state root ');
            }
            
            // check callerKey of merkle proof
            if (merkleProof.callerKey != keccak256(abi.encodePacked(proofs.storageAccount.addr))) {
                return (hashes.isValid);
            }
            hashes.storageAccount = decodeAccount(
                    proofs.storageAccount
            );
            if (executionState.isCREATE) {
                toAddress = generateAddressForCREATE(
                    proofs.storageAccount.addr, hashes.storageAccount.nonce
                );
            } else if (executionState.isCREATE2) {
                // get salt from stack of the before step
                hashes.saltForCREATE2 = executionState.stack[0];
                toAddress = generateAddressForCREATE2(
                        proofs.storageAccount.addr,
                        hashes.saltForCREATE2,
                        // TODO: verifying initCodeHash
                        executionState.initCodeHash
                );
            } else {
                // get toAddress from the stack of before step
                toAddress = address(uint160(uint256(executionState.stack[5])));
            }
         
            if (executionState.beforeCalleeAccount.addr != toAddress
                || executionState.storageAccount.addr != toAddress) {
                return (hashes.isValid);
            }
            // check calleeKey of merkle proof with toAddress
            if (merkleProof.calleeKey != keccak256(abi.encodePacked(toAddress))) {
                return (hashes.isValid);
            }
            
            // get call value from the stack of before step
            if (executionState.isCREATE) {
                val = uint(executionState.stack[2]);
            } else if (executionState.isCREATE2) {
                val = uint(executionState.stack[3]);
            } else {
                val = uint(executionState.stack[4]);
            }
           
            callerBeforeLeaf = keccak256(abi.encodePacked(proofs.storageAccount.rlpVal));
            calleeBeforeLeaf = keccak256(abi.encodePacked(executionState.beforeCalleeAccount.rlpVal));

            // check beforeLeaf of merkle proof
            if (merkleProof.callerBeforeLeaf != callerBeforeLeaf ||
                merkleProof.calleeBeforeLeaf != calleeBeforeLeaf) {
                return (hashes.isValid);
            }
            MerkelizerStorage.Account memory callerAccount = decodeAccount(
                proofs.storageAccount
            );
            MerkelizerStorage.Account memory calleeAccount = decodeAccount(
                executionState.beforeCalleeAccount
            );

            callerAccount.balance = callerAccount.balance.sub(val);
            calleeAccount.balance = calleeAccount.balance.add(val);

            callerBalance = callerAccount.balance;
            calleeBalance = calleeAccount.balance;

            callerRlpVal = encodeAccount(callerAccount);
            calleeRlpVal = encodeAccount(calleeAccount);

            callerAfterLeaf = keccak256(abi.encodePacked(callerRlpVal));
            calleeAfterLeaf = keccak256(abi.encodePacked(calleeRlpVal));

            // check afterLeaf of merkle proof
            if (merkleProof.callerAfterLeaf != callerAfterLeaf ||
                merkleProof.calleeAfterLeaf != calleeAfterLeaf) {
                return (hashes.isValid);
            }
            // check runtimeStackHash of after step
            hashes.runtimeStackHash = MerkelizerStorage.runtimeStackHash(
                executionState.storageAccount.addr,
                executionState.bytecodeAccount.addr,
                proofs.runtimeStackHash
            );
            if (hashes.runtimeStackHash != executionState.runtimeStackHash) {
                return (hashes.isValid);
            }
            // check accountHash of after step
            hashes.accountHash = MerkelizerStorage.accountHash(
                executionState.storageAccount.addr,
                executionState.storageAccount.rlpVal,
                executionState.bytecodeAccount.addr,
                executionState.bytecodeAccount.rlpVal
            );
            if (hashes.accountHash != executionState.accountHash) {
                return (hashes.isValid);
            }

            hashes.isValid = verifyCALLVALUE (
                merkleProof.callerKey,
                merkleProof.calleeKey,
                merkleProof.callerBeforeLeaf,
                merkleProof.callerAfterLeaf,
                merkleProof.calleeBeforeLeaf,
                merkleProof.calleeAfterLeaf,
                merkleProof.beforeRoot,
                merkleProof.intermediateRoot,
                merkleProof.afterRoot,
                merkleProof.callerSiblings,
                merkleProof.calleeSiblings
            );
            return (hashes.isValid);
        } else {
            if ((!executionState.isCREATE && !executionState.isCREATE2) && (executionState.callStart || executionState.callEnd)) {
                // in the case of CALLStart and CALLEnd, check here.
                require(proofs.stateRoot == executionState.stateRoot, 'they must be same state root ');
                require(merkleProof.beforeRoot == proofs.stateRoot, 'they must be same state root ');
            }
            if (executionState.callStart) {
                // check runtimeStackHash of after step
                hashes.runtimeStackHash = MerkelizerStorage.runtimeStackHash(
                    executionState.storageAccount.addr,
                    executionState.bytecodeAccount.addr,
                    proofs.runtimeStackHash
                );
                if (hashes.runtimeStackHash != executionState.runtimeStackHash) {
                    return (hashes.isValid);
                }
                // check callerKey of merkle proof
                if (executionState.isDELEGATECALL) {
                    if (merkleProof.callerKey != keccak256(abi.encodePacked(proofs.storageAccount.addr))) {
                        return (hashes.isValid);
                    }
                } else if (executionState.isCALL && !executionState.isCREATE && !executionState.isCREATE2) {
                    toAddress = address(uint160(uint256(executionState.stack[5])));
                    if (merkleProof.callerKey != keccak256(abi.encodePacked(toAddress))) {
                        return (hashes.isValid);
                    }
                }
            } else if (executionState.callEnd) {
                // check runtimeStackHash of after step
                hashes.runtimeStackHash = MerkelizerStorage.runtimeStackHash(
                    executionState.storageAccount.addr,
                    executionState.bytecodeAccount.addr,
                    executionState.previousRuntimeStackHash
                );
                if (hashes.runtimeStackHash != proofs.previousRuntimeStackHash) {
                    return (hashes.isValid);
                }
                // check callerKey of merkle proof
                if (merkleProof.callerKey != keccak256(abi.encodePacked(
                        executionState.storageAccount.addr
                    ))) {
                    return (hashes.isValid);
                }
            }
            
            if ((executionState.isCREATE || executionState.isCREATE2) && executionState.callStart) {
                MerkelizerStorage.Account memory storageAccount = decodeAccount(
                    proofs.storageAccount
                );
                // check created address
                if (executionState.isCREATE) {
                    if (merkleProof.callerKey != keccak256(abi.encodePacked(
                        generateAddressForCREATE(
                            proofs.storageAccount.addr, storageAccount.nonce
                        ))
                    )) {
                        return (hashes.isValid);
                    }
                } else if (executionState.isCREATE2) {
                    // get salt from stack of the before step
                    salt = executionState.stack[0];
                    hashes.saltForCREATE2 = executionState.stack[0];
                    createdAddress = generateAddressForCREATE2(
                            proofs.storageAccount.addr,
                            hashes.saltForCREATE2,
                            // TODO: verifying initCodeHash
                            executionState.initCodeHash
                    );
                    
                    if (merkleProof.callerKey != keccak256(abi.encodePacked(
                        generateAddressForCREATE2(
                            proofs.storageAccount.addr,
                            hashes.saltForCREATE2,
                            executionState.initCodeHash
                        ))
                    )) {
                        return (hashes.isValid);
                    }
                }
                hashes.isValid = verifyCREATE(
                    merkleProof.callerKey,
                    merkleProof.callerBeforeLeaf,
                    merkleProof.callerAfterLeaf,
                    proofs.stateRoot,
                    executionState.stateRoot,
                    merkleProof.callerSiblings
                );
                
                return (hashes.isValid);
            } else {
                // check calleeKey
                if (merkleProof.calleeKey != keccak256(abi.encodePacked(
                    executionState.bytecodeAccount.addr)
                )) {
                    return (hashes.isValid);
                }

                // check callerBeforeLeaf of merkle proof
                hashes.callerBeforeLeaf = keccak256(abi.encodePacked(
                    executionState.storageAccount.rlpVal
                ));
                if (hashes.callerBeforeLeaf != merkleProof.callerBeforeLeaf) {
                    return (hashes.isValid);
                }
                // check calleeBeforeLeaf of merkle proof
                hashes.calleeBeforeLeaf = keccak256(abi.encodePacked(
                    executionState.bytecodeAccount.rlpVal
                ));
                if (hashes.calleeBeforeLeaf != merkleProof.calleeBeforeLeaf) {
                    return (hashes.isValid);
                }
                
                hashes.isValid = verifyCALL(
                    merkleProof.callerKey,
                    merkleProof.calleeKey,
                    merkleProof.callerBeforeLeaf,
                    merkleProof.calleeBeforeLeaf,
                    merkleProof.beforeRoot,
                    merkleProof.callerSiblings,
                    merkleProof.calleeSiblings
                );
                return (hashes.isValid);
            }
        }
    }

    /*
     * if they agree on `left` but not on `right`,
     * submitProof (on-chain) verification should be called by challenger and solver
     * to decide on the outcome.
     *
     * Requirements:
     *  - last execution step must end with either REVERT, RETURN or STOP to be considered complete
     *  - any execution step which does not have errno = 0 or errno = 0x07 (REVERT)
     *    is considered invalid
     *  - the left-most (first) execution step must be a `Merkelizer.initialStateHash`
     *
     * Note: if that doesnt happen, this will finally timeout and a final decision is made
     *       in `claimTimeout`.
     */
    // solhint-disable-next-line code-complexity
    function submitProof(
        bytes32 disputeId,
        Proofs memory proofs,
        MerkelizerStorage.ExecutionState memory executionState,
        MerkleProof memory merkleProof
        // solhint-disable-next-line function-max-lines
    ) public onlyPlaying(disputeId) {
        Dispute storage dispute = disputes[disputeId];
        require(dispute.treeDepth == 0, "Not at leaf yet");
        Hashes memory hashes;

        if (!(executionState.callStart || executionState.callEnd)) {
            // TODO: all sanity checks should go in a common function
            if (executionState.stack.length > executionState.stackSize) {
                return;
            }
            if (executionState.mem.length > executionState.memSize) {
                return;
            }
        }
        // TODO: verify all inputs, check access pattern(s) for memory, calldata, stack
        hashes.dataHash = executionState.data.length != 0 ? MerkelizerStorage.dataHash(executionState.data) : proofs.dataHash;
        hashes.memHash = executionState.mem.length != 0 ? MerkelizerStorage.memHash(executionState.mem) : proofs.memHash;
        inputHash = getInputHash(
            executionState,
            proofs,
            hashes
        );
        
        if ((inputHash != dispute.solver.left && inputHash != dispute.challenger.left) ||
            ((dispute.state & START_OF_EXECUTION) != 0 && inputHash != dispute.initialStateHash)) {
            return;
        }
        if (dispute.witness != bytes32(0)) {
            if (inputHash != dispute.witness) {
                return;
            }
        }

        if (executionState.callStart || executionState.callEnd) {
            hashes.isValid = verifyAccount(
                proofs,
                executionState,
                merkleProof
            );
            // @dev if failed to verifyAccount, it is judged immediately.
            if (hashes.isValid) {
                if (msg.sender == address(dispute.challengerAddr)) {
                    dispute.state |= CHALLENGER_VERIFIED;
                } else if (msg.sender != address(dispute.challengerAddr)) {
                    dispute.state |= SOLVER_VERIFIED;
                }

                if (dispute.state & SOLVER_VERIFIED != 0) {
                    enforcer.result(dispute.executionId, true, dispute.challengerAddr);
                } else {
                    enforcer.result(dispute.executionId, false, dispute.challengerAddr);
                }
            } else {
                return;
            }
        } else if (executionState.isStorageDataChanged) {
            require(merkleProof.beforeRoot == proofs.storageRoot, 'they must be same state root ');
            require(merkleProof.afterRoot == executionState.storageRoot, 'they must be same state root ');
            // storage key check
            if (merkleProof.callerKey != keccak256(abi.encodePacked(executionState.stack[1]))) {
                return;
            }
            // storage val check
            if (merkleProof.callerAfterLeaf != keccak256(abi.encodePacked(executionState.stack[0]))) {
                return;
            }
            // verify storageRoot
            hashes.isStorageValid = verifySSTORE (
                merkleProof.callerKey,
                merkleProof.callerBeforeLeaf,
                merkleProof.callerAfterLeaf,
                merkleProof.beforeRoot,
                merkleProof.afterRoot,
                merkleProof.callerSiblings
            );
            if (hashes.isStorageValid) {
                // account proof check
                hashedKey = keccak256(abi.encodePacked(proofs.storageAccount.addr));
                hashes.beforeLeaf = keccak256(abi.encodePacked(proofs.storageAccount.rlpVal));
                
                MerkelizerStorage.Account memory storageAccount = decodeAccount(
                    proofs.storageAccount
                );
                
                storageAccount.storageRoot = abi.encodePacked(merkleProof.afterRoot);
                runtimeRlpVal = encodeAccount(storageAccount);
                
                hashes.afterLeaf = keccak256(abi.encodePacked(runtimeRlpVal));
                hashes.siblings = proofs.storageAccount.siblings;
                // verify stateRoot
                hashes.isValid = verifySSTORE (
                    hashedKey,
                    hashes.beforeLeaf,
                    hashes.afterLeaf,
                    proofs.stateRoot,
                    executionState.stateRoot,
                    hashes.siblings
                );
            } else {
                return;
            }
            if (hashes.isValid) {
                if (msg.sender == address(dispute.challengerAddr)) {
                    dispute.state |= CHALLENGER_VERIFIED;
                } else if (msg.sender != address(dispute.challengerAddr)) {
                    dispute.state |= SOLVER_VERIFIED;
                }

                if (dispute.state & SOLVER_VERIFIED != 0) {
                    enforcer.result(dispute.executionId, true, dispute.challengerAddr);
                } else {
                    enforcer.result(dispute.executionId, false, dispute.challengerAddr);
                }
            } else {
                return;
            }
        } else {
            if (executionState.callDepth == 0 && executionState.isFirstStep) {
                require(proofs.stateRoot == executionState.stateRoot, 'they must be same state root ');
                require(merkleProof.beforeRoot == proofs.stateRoot, 'they must be same state root ');
                // check callerKey of merkle proof
                if (merkleProof.callerKey != keccak256(abi.encodePacked(proofs.storageAccount.addr))) {
                    return;
                }
                // check callerBeforeLeaf of merkle proof
                if (merkleProof.callerBeforeLeaf != keccak256(abi.encodePacked(proofs.storageAccount.rlpVal))) {
                    return;
                }

                hashes.isValid = checkMembership(
                    merkleProof.callerKey,
                    merkleProof.callerBeforeLeaf,
                    merkleProof.beforeRoot,
                    merkleProof.callerSiblings
                );
                
                // return if chcek failed.
                if (!hashes.isValid) {
                    return;
                }
            }

            require(proofs.stateRoot == executionState.stateRoot, 'they must be same state root ');
            if (proofs.runtimeStackHash != executionState.runtimeStackHash) {
                return;
            }
            if (proofs.accountHash != executionState.accountHash) {
                return;
            }
            // check bytecode
            MerkelizerStorage.Account memory bytecodeAccount = decodeAccount(proofs.bytecodeAccount);
            hashes.codeHash = bytesToBytes32(bytecodeAccount.codeHash, 0);
            if (executionState.callDepth != 0) {
                if (hashes.codeHash != proofs.calleeCodeHash) {
                    return;
                }
            } else {
                if (hashes.codeHash != dispute.codeHash) {
                    return;
                }
            }
            
            EVM memory evm;

            if (executionState.callDepth != 0) {
                evm.code = verifyCode(
                    proofs.calleeCodeHash,
                    proofs.codeFragments,
                    proofs.codeProof,
                    proofs.codeByteLength
                );
            } else {
                evm.code = verifyCode(
                    dispute.codeHash,
                    proofs.codeFragments,
                    proofs.codeProof,
                    proofs.codeByteLength
                );
            }

            if ((dispute.state & END_OF_EXECUTION) != 0) {
                hashes.opcode = evm.code.getOpcodeAt(executionState.pc);

                if (hashes.opcode != OP_REVERT && hashes.opcode != OP_RETURN && hashes.opcode != OP_STOP) {
                    return;
                }
            }
            
            HydratedState memory hydratedState = initHydratedState(evm);

            hydratedState.stackHash = proofs.stackHash;
            hydratedState.memHash = hashes.memHash;
            hydratedState.tStorageHash = hashes.tStorageHash;
            hydratedState.logHash = executionState.logHash;

            evm.data = executionState.data;
            evm.gas = executionState.gasRemaining;
            evm.caller = DEFAULT_CALLER;
            evm.target = DEFAULT_CONTRACT_ADDRESS;
            evm.stack = EVMStack.fromArray(executionState.stack);
            evm.mem = EVMMemory.fromArray(executionState.mem);
            evm.returnData = executionState.returnData;
            evm.tStorage = EVMStorageToArray.fromArrayForHash(executionState.tStorage);
            evm.isStorageReset = executionState.isStorageReset;
            
            _run(evm, executionState.pc, 1);

            if (evm.errno != NO_ERROR && evm.errno != ERROR_STATE_REVERTED) {
                return;
            }

            executionState.pc = evm.pc;
            executionState.returnData = evm.returnData;
            executionState.gasRemaining = evm.gas;
            executionState.logHash = hydratedState.logHash;
            
            if (executionState.stack.length > executionState.stackSize) {
                return;
            }

            hashes.stackSize = executionState.stackSize - executionState.stack.length;

            executionState.stackSize = evm.stack.size + hashes.stackSize;
            // stackSize cant be bigger than 1024 (stack limit)
            if (executionState.stackSize > MAX_STACK_SIZE) {
                return;
            }

            // will be changed once we land merkle tree for memory
            if (evm.mem.size > 0) {
                executionState.memSize = evm.mem.size;
            }
           
            hashes.resultHash = getStateHash(executionState, hydratedState, proofs, hashes.dataHash);

            if (hashes.resultHash != dispute.solver.right && hashes.resultHash != dispute.challenger.right) {
                return;
            }

            if (hashes.resultHash == dispute.solver.right && executionState.memSize < MAX_MEM_WORD_COUNT) {
                dispute.state |= SOLVER_VERIFIED;
            }

            if (hashes.resultHash == dispute.challenger.right) {
                dispute.state |= CHALLENGER_VERIFIED;
            }

            if (dispute.state & SOLVER_VERIFIED != 0) {
                enforcer.result(dispute.executionId, true, dispute.challengerAddr);
            } else {
                enforcer.result(dispute.executionId, false, dispute.challengerAddr);
            }
        }
    }

    function bytesToBytes32(bytes memory b, uint offset) private pure returns (bytes32) {
        bytes32 out;

        for (uint i = 0; i < 32; i++) {
            out |= bytes32(b[offset + i] & 0xFF) >> (i * 8);
        }
        return out;
    }

    function getInputHash(
        MerkelizerStorage.ExecutionState memory executionState,
        Proofs memory proofs,
        Hashes memory hashes
    ) internal pure returns (bytes32) {
        bytes32 stackHash;
        bytes32 runtimeStackHash;
        bytes32 accountHash;

        if (executionState.callStart || executionState.callEnd) {
            stackHash = proofs.stackHash;
        } else {
            stackHash = executionState.stackHash(proofs.stackHash);
        }

        runtimeStackHash = MerkelizerStorage.runtimeStackHash(
            proofs.storageAccount.addr, proofs.bytecodeAccount.addr, proofs.previousRuntimeStackHash
        );
        accountHash = MerkelizerStorage.accountHash(
            proofs.storageAccount.addr,
            proofs.storageAccount.rlpVal,
            proofs.bytecodeAccount.addr,
            proofs.bytecodeAccount.rlpVal
        );
                
        bytes32 intermediateHash = executionState.intermediateHash(
            stackHash,
            hashes.memHash,
            hashes.dataHash,
            proofs.storageRoot,
            proofs.stateRoot,
            runtimeStackHash,
            accountHash
        );
        bytes32 envHash = executionState.envHash();
        return executionState.stateHash(
            intermediateHash,
            envHash
        );
    }
    
    function getStateHash(
        MerkelizerStorage.ExecutionState memory _executionState,
        HydratedState memory _hydratedState,
        Proofs memory proofs,
        bytes32 _dataHash
    ) internal pure returns (bytes32) {
        bytes32 runtimeStackHash = MerkelizerStorage.runtimeStackHash(
            _executionState.storageAccount.addr,
            _executionState.bytecodeAccount.addr,
            _executionState.previousRuntimeStackHash
        );
        bytes32 accountHash = MerkelizerStorage.accountHash(
            _executionState.storageAccount.addr,
            _executionState.storageAccount.rlpVal,
            _executionState.bytecodeAccount.addr,
            _executionState.bytecodeAccount.rlpVal
        );
        bytes32 intermediateHash = _executionState.intermediateHash(
            _hydratedState.stackHash,
            _hydratedState.memHash,
            _dataHash,
            _executionState.storageRoot,
            _executionState.stateRoot,
            runtimeStackHash,
            accountHash
        );
        bytes32 envHash = _executionState.envHash();
        return _executionState.stateHash(
            intermediateHash,
            envHash
        );
    }

    /*
     * When claimTimeout is called, the dispute must not be resolved
     *  Hence, there are 3 cases:
     *  - Nobody has responded
     *  - Solver has responded, challenger hasn't: Solver wins
     *  - Solver has not responded, challenger has: Challenger wins
     * The case both have responded is not exist because if both responded, updateRound would has been called
     *  and reset timeout and states
     * The case "Nobody has responded" has 2 subcases:
     *  - Before last turn: Solver wins, because we assume that challenger is the one who requested the dispute and has more responsibility
     *  - Last turn: Challenger wins. Here, somebody should call submitProof. If it is not called, it should be solver's fault,
     *      because it could be something only solver knows
     */
    function claimTimeout(bytes32 disputeId) public {
        Dispute storage dispute = disputes[disputeId];

        require(dispute.timeout > 0, "dispute not exist");
        require(dispute.timeout < block.timestamp, "not timed out yet");
        require(
            (dispute.state & SOLVER_VERIFIED) == 0 && (dispute.state & CHALLENGER_VERIFIED) == 0,
            "already notified enforcer"
        );

        bool solverWins;

        if ((dispute.state & SOLVER_RESPONDED) != 0) {
            solverWins = true;
        } else if ((dispute.state & CHALLENGER_RESPONDED) != 0) {
            solverWins = false;
        } else {
            solverWins = (dispute.treeDepth > 0);
        }

        if (solverWins) {
            dispute.state |= SOLVER_VERIFIED;
        } else {
            dispute.state |= CHALLENGER_VERIFIED;
        }

        enforcer.result(dispute.executionId, solverWins, dispute.challengerAddr);
    }

    /**
      * @dev refresh timeout of dispute
      */
    function getTimeout() internal view returns (uint256) {
        return block.timestamp + timeoutDuration;
    }

    /**
      * @dev updateRound runs every time after receiving a respond
      *         assume that both solver and challenger have the same tree depth
      */
    // solhint-disable-next-line code-complexity, function-max-lines
    function updateRound(bytes32 disputeId, Dispute storage dispute, ComputationPath memory witnessPath) internal {
        if ((dispute.state & SOLVER_RESPONDED) == 0 || (dispute.state & CHALLENGER_RESPONDED) == 0) {
            return;
        }

        // left can not be zero
        if (dispute.solver.left == bytes32(0)) {
            enforcer.result(dispute.executionId, false, dispute.challengerAddr);
            dispute.state |= CHALLENGER_VERIFIED;
            return;
        }
        if (dispute.challenger.left == bytes32(0)) {
            enforcer.result(dispute.executionId, true, dispute.challengerAddr);
            dispute.state |= SOLVER_VERIFIED;
            return;
        }

        if (dispute.witness != bytes32(0)) {
            require(
                keccak256(abi.encodePacked(witnessPath.left, witnessPath.right)) == dispute.witness
            );

            dispute.witness = witnessPath.right;
        }

        // refresh state and timeout
        dispute.timeout = getTimeout();
        dispute.state ^= SOLVER_RESPONDED | CHALLENGER_RESPONDED;

        dispute.treeDepth -= 1;

        if ((dispute.solver.left == dispute.challenger.left) &&
            (dispute.solver.right != 0) &&
            (dispute.challenger.right != 0)) {
            // following right
            dispute.witness = dispute.solver.left;
            dispute.solverPath = dispute.solver.right;
            dispute.challengerPath = dispute.challenger.right;

            if ((dispute.state & START_OF_EXECUTION) != 0) {
                dispute.state ^= START_OF_EXECUTION;
            }
        } else {
            // following left
            dispute.solverPath = dispute.solver.left;
            dispute.challengerPath = dispute.challenger.left;

            if (dispute.solver.right != 0) {
                if ((dispute.state & END_OF_EXECUTION) != 0) {
                    dispute.state ^= END_OF_EXECUTION;
                }
            }
        }
        emit DisputeNewRound(disputeId, dispute.timeout, dispute.solverPath, dispute.challengerPath);
    }
    /// @dev TODO: fix bug(zeroHash)
    /// @dev Verify FragmentTree for contract bytecode.
    /// `codeFragments` must be power of two and consists of `slot/pos`, `value`.
    /// If `codeHash`'s last 12 bytes are zero, `codeHash` assumed to be a contract address
    /// and returns with `EVMCode.fromAddress(...)`.
    /// @return EVMCode.Code
    function verifyCode(
        bytes32 codeHash,
        bytes32[] memory codeFragments,
        bytes32[] memory codeProofs,
        uint256 codeByteLength
        // solhint-disable-next-line function-max-lines
    ) internal view returns (EVMCode.Code memory) {
        // it's a contract address, pull code from there
        if ((uint256(codeHash) & 0xffffffffffffffffffffffff) == 0) {
            return EVMCode.fromAddress(address(bytes20(codeHash)));
        }

        // Codes will be supplied by the user
        // TODO: we should support compressed-proofs in the future
        // to save quite a bit of computation

        // Enforce max. leaveCount here? :)
        uint256 leaveCount = ((codeByteLength + 31) / 32);
        require(leaveCount > 0);

        // leaveCount should round up to the next highest power of 2.
        leaveCount--;
        leaveCount |= leaveCount >> 1;
        leaveCount |= leaveCount >> 2;
        leaveCount |= leaveCount >> 4;
        leaveCount |= leaveCount >> 8;
        leaveCount |= leaveCount >> 16;
        leaveCount++;
        //leaveCount = leaveCount + leaveCount % 2;

        // calculate tree depth
        uint256 treeDepth = 0;
        for (; leaveCount != 1; leaveCount >>= 1) {
            treeDepth++;
        }

        require(codeFragments.length % 2 == 0);
        require(codeProofs.length == ((codeFragments.length / 2) * (treeDepth)));

        assembly {
            // save memory slots, we are gonna use them
            let tmp := mload(0x40)
            mstore(0x40, codeByteLength)

            let codeFragLen := mload(codeFragments)
            let codeFrags := add(codeFragments, 0x20)
            let proofs := add(codeProofs, 0x20)
            for { let x := 0 } lt(x, codeFragLen) { x := add(x, 2) } {
                let fragPtr := add(codeFrags, mul(x, 0x20))
                let slot := mload(fragPtr)

                mstore(0x00, mload(add(fragPtr, 0x20)))
                mstore(0x20, slot)

                let hash := keccak256(0x00, 0x60)

                for { let i := 0 } lt(i, treeDepth) { i := add(i, 1) } {
                    mstore(0x00, mload(proofs))
                    mstore(0x20, hash)

                    if iszero(mod(slot, 2)) {
                        mstore(0x00, hash)
                        mstore(0x20, mload(proofs))
                    }

                    hash := keccak256(0x00, 0x40)
                    //slot := shr(slot, 1)
                    // bitwise-right (slot << 1)
                    slot := div(slot, exp(2, 1))
                    proofs := add(proofs, 0x20)
                }

                // require hash == codeHash
                if iszero(eq(hash, codeHash)) {
                    revert(0, 0)
                }
            }
            // restore memory slots
            mstore(0x40, tmp)
        }

        return EVMCode.fromArray(codeFragments, codeByteLength);
    }
}