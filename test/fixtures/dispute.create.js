'use strict';

const HydratedRuntime = require('./../../utils/HydratedRuntime');
const Merkelizer = require('../../utils/Merkelizer');
const OP = require('../../utils/constants');
const utils = require('ethereumjs-util');
const BN = utils.BN;
const debug = require('debug')('dispute-test');
const web3 = require('web3');
const _ = require('lodash');

module.exports = (callback) => {
  describe('Fixture for Dispute/Verifier Logic #1', function () { 

    const code = '608060405234801561001057600080fd5b50600436106100365760003560e01c80636ea9bfc51461003b578063c6dad082146100f3575b600080fd5b6100f16004803603602081101561005157600080fd5b810190808035906020019064010000000081111561006e57600080fd5b82018360208201111561008057600080fd5b803590602001918460208302840111640100000000831117156100a257600080fd5b919080806020026020016040519081016040528093929190818152602001838360200280828437600081840152601f19601f82011690508083019250505050505050919291929050505061013d565b005b6100fb6101ae565b604051808273ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200191505060405180910390f35b602060405190810160405280828152506000803373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060008201518160000190805190602001906101a79291906102c8565b5090505050565b6000806101b9610315565b604051809103906000f0801580156101d5573d6000803e3d6000fd5b5090508073ffffffffffffffffffffffffffffffffffffffff1663d88b06db6000803373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020019081526020016000206000016040518263ffffffff1660e01b81526004018080602001828103825283818154815260200191508054801561028957602002820191906000526020600020905b815481526020019060010190808311610275575b505092505050600060405180830381600087803b1580156102a957600080fd5b505af11580156102bd573d6000803e3d6000fd5b505050508091505090565b828054828255906000526020600020908101928215610304579160200282015b828111156103035782518255916020019190600101906102e8565b5b5090506103119190610325565b5090565b6040516102388061034b83390190565b61034791905b8082111561034357600081600090555060010161032b565b5090565b9056fe608060405234801561001057600080fd5b506001600081905550610210806100286000396000f3fe608060405234801561001057600080fd5b50600436106100365760003560e01c806345f0a44f1461003b578063d88b06db1461007d575b600080fd5b6100676004803603602081101561005157600080fd5b8101908080359060200190929190505050610135565b6040518082815260200191505060405180910390f35b6101336004803603602081101561009357600080fd5b81019080803590602001906401000000008111156100b057600080fd5b8201836020820111156100c257600080fd5b803590602001918460208302840111640100000000831117156100e457600080fd5b919080806020026020016040519081016040528093929190818152602001838360200280828437600081840152601f19601f820116905080830192505050505050509192919290505050610158565b005b60018181548110151561014457fe5b906000526020600020016000915090505481565b806001908051906020019061016e929190610172565b5050565b8280548282559060005260206000209081019282156101ae579160200282015b828111156101ad578251825591602001919060010190610192565b5b5090506101bb91906101bf565b5090565b6101e191905b808211156101dd5760008160009055506001016101c5565b5090565b9056fea165627a7a72305820279a87846d67f2031b93595a4742c6d005ecc41e68b43680a27ca666f8b72ec00029a165627a7a72305820eb029d0504ee83aabbb206827eaa7ba68d70ba9b20cee4023d07953c8e5480590029';
    const data = '0xc6dad082';
    const tStorage = [];

    const accounts = [
        // caller
        {
          address: '0x9069B7d897B6f66332D15821aD2f95609c81E59a',
          code: code,
          tStorage: tStorage,
          nonce: new BN(0x2, 16),
          balance: new BN(0x64, 16),
          storageRoot: OP.ZERO_HASH,
          codeHash: OP.ZERO_HASH
        },
    ];

    let steps;
    let copy;
    let calleeCopy;
    let merkle;
    
    beforeEach(async () => {
      const runtime = new HydratedRuntime();
      steps = await runtime.run({ accounts, code, data, pc: 0, tStorage: tStorage, pc: 0 });
      copy = _.cloneDeep(steps);
      // opcode CREATE step 58, SSTORE 14, SLOAD 116, 124
      calleeCopy = _.cloneDeep(steps[58].calleeSteps);
      merkle = new Merkelizer().run(steps, code, data, tStorage);
    });

    // it('solver has an wrong stateProof at FirstStep', async () => {
    //   const wrongExecution = copy;
     
    //   wrongExecution[0].stateRoot = Buffer.alloc(32);
    //   wrongExecution[0].callerAccount.rlpVal = Buffer.alloc(32);
      
    //   const solverMerkle = new Merkelizer().run(wrongExecution, code, data, tStorage);
    //   await callback(code, data, tStorage, solverMerkle, merkle, 'challenger');
    // });

    // it('challenger has an wrong stateProof at FirstStep', async () => {
    //   const wrongExecution = copy;
     
    //   wrongExecution[0].stateRoot = Buffer.alloc(32);
    //   wrongExecution[0].callerAccount.rlpVal = Buffer.alloc(32);

    //   const challengerMerkle = new Merkelizer().run(wrongExecution, code, data, tStorage);
    //   await callback(code, data, tStorage, merkle, challengerMerkle, 'solver');
    // });

    // it('solver has an wrong storageProof at SSTORE', async () => {
    //   const wrongExecution = copy;
    //   const wrongCalleeStep = calleeCopy;

    //   wrongCalleeStep[14].storageRoot = Buffer.alloc(32);
    //   wrongCalleeStep[14].storageProof.storageRoot = Buffer.alloc(32);
    //   wrongExecution[58].calleeSteps = wrongCalleeStep;
            
    //   const solverMerkle = new Merkelizer().run(wrongExecution, code, data, tStorage);
    //   await callback(code, data, tStorage, solverMerkle, merkle, 'challenger');
    // });

    // it('challenger has an wrong storageProof at SSTORE', async () => {
    //   const wrongExecution = copy;
    //   const wrongCalleeStep = calleeCopy;
      
    //   wrongCalleeStep[14].storageRoot = Buffer.alloc(32);
    //   wrongCalleeStep[14].storageProof.storageRoot = Buffer.alloc(32);
    //   wrongExecution[58].calleeSteps = wrongCalleeStep;

    //   const challengerMerkle = new Merkelizer().run(wrongExecution, code, data, tStorage);
    //   await callback(code, data, tStorage, merkle, challengerMerkle, 'solver');
    // });

    // it('solver has an wrong stateProof at CALLStart', async () => {
    //   const wrongExecution = copy;
    //   const wrongCalleeStep = calleeCopy;

    //   wrongCalleeStep[0].stateRoot = Buffer.alloc(32);
    //   wrongCalleeStep[0].callerAccount.rlpVal = Buffer.alloc(32);
    //   wrongExecution[58].calleeSteps = wrongCalleeStep;
    //   const solverMerkle = new Merkelizer().run(wrongExecution, code, data, tStorage);
    //   await callback(code, data, tStorage, solverMerkle, merkle, 'challenger');
    // });

    it('challenger has an wrong stateProof at CALLStart', async () => {
      const wrongExecution = copy;
      const wrongCalleeStep = calleeCopy;

      wrongCalleeStep[0].stateRoot = Buffer.alloc(32);
      wrongCalleeStep[0].callerAccount.rlpVal = Buffer.alloc(32);
      wrongExecution[58].calleeSteps = wrongCalleeStep;
      const challengerMerkle = new Merkelizer().run(wrongExecution, code, data, tStorage);
      await callback(code, data, tStorage, merkle, challengerMerkle, 'solver');
    });

    // it('solver has an wrong stateProof at CALLEnd', async () => {
    //   const wrongExecution = copy;
    //   wrongExecution[58].stateRoot = Buffer.alloc(32);
    //   wrongExecution[58].callerAccount.rlpVal = Buffer.alloc(32);
    //   const solverMerkle = new Merkelizer().run(wrongExecution, code, data, tStorage);
    //   await callback(code, data, tStorage, solverMerkle, merkle, 'challenger');
    // });

    // it('challenger has an wrong stateProof at CALLEnd', async () => {
    //   const wrongExecution = copy;
    //   wrongExecution[58].stateRoot = Buffer.alloc(32);
    //   wrongExecution[58].callerAccount.rlpVal = Buffer.alloc(32);
    //   const challengerMerkle = new Merkelizer().run(wrongExecution, code, data, tStorage);
    //   await callback(code, data, tStorage, merkle, challengerMerkle, 'solver');
    // });

    // it('solver first step missing in CALLEE', async () => {
    //   const wrongExecution = copy;
    //   const wrongCalleeStep = calleeCopy;

    //   wrongCalleeStep.shift();
    //   wrongExecution[58].calleeSteps = wrongCalleeStep;
    //   const solverMerkle = new Merkelizer().run(wrongExecution, code, data, tStorage);
    //   await callback(code, data, tStorage, solverMerkle, merkle, 'challenger');
    // });    

    // it('challenger first step missing in CALLEE', async () => {
    //   const wrongExecution = copy;
    //   const wrongCalleeStep = calleeCopy;

    //   wrongCalleeStep.shift();
    //   wrongExecution[58].calleeSteps = wrongCalleeStep;
    //   const challengerMerkle = new Merkelizer().run(wrongExecution, code, data, tStorage);
    //   await callback(code, data, tStorage, merkle, challengerMerkle, 'solver');
    // });

    // it('solver has an wrong afterStateRoot at FirstStep', async () => {
    //   const wrongExecution = copy;
     
    //   wrongExecution[0].stateRoot = Buffer.alloc(32);
            
    //   const solverMerkle = new Merkelizer().run(wrongExecution, code, data, tStorage);
    //   await callback(code, data, tStorage, solverMerkle, merkle, 'challenger');
    // });

    // it('challenger has an wrong afterStateRoot at FirstStep', async () => {
    //   const wrongExecution = copy;
     
    //   wrongExecution[0].stateRoot = Buffer.alloc(32);
     
    //   const challengerMerkle = new Merkelizer().run(wrongExecution, code, data, tStorage);
    //   await callback(code, data, tStorage, merkle, challengerMerkle, 'solver');
    // });

    // it('solver has an wrong afterStateRoot at CALLStart', async () => {
    //   const wrongExecution = copy;
    //   const wrongCalleeStep = calleeCopy;

    //   wrongCalleeStep[0].stateRoot = Buffer.alloc(32);
    //   wrongExecution[58].calleeSteps = wrongCalleeStep;

    //   const solverMerkle = new Merkelizer().run(wrongExecution, code, data, tStorage);
    //   await callback(code, data, tStorage, solverMerkle, merkle, 'challenger');
    // });

    // it('challenger has an wrong afterStateRoot at CALLStart', async () => {
    //   const wrongExecution = copy;
    //   const wrongCalleeStep = calleeCopy;

    //   wrongCalleeStep[0].stateRoot = Buffer.alloc(32);
    //   wrongExecution[58].calleeSteps = wrongCalleeStep;
      
    //   const challengerMerkle = new Merkelizer().run(wrongExecution, code, data, tStorage);
    //   await callback(code, data, tStorage, merkle, challengerMerkle, 'solver');
    // });

    // it('solver has an wrong afterStateRoot at CALLEnd', async () => {
    //   const wrongExecution = copy;
      
    //   wrongExecution[58].stateRoot = Buffer.alloc(32);
    //   wrongExecution[58].callerAccount.rlpVal = Buffer.alloc(32);

    //   const solverMerkle = new Merkelizer().run(wrongExecution, code, data, tStorage);
    //   await callback(code, data, tStorage, solverMerkle, merkle, 'challenger');
    // });

    // it('challenger has an wrong afterStateRoot at CALLEnd', async () => {
    //   const wrongExecution = copy;
      
    //   wrongExecution[58].stateRoot = Buffer.alloc(32);
    //   wrongExecution[58].callerAccount.rlpVal = Buffer.alloc(32);
      
    //   const challengerMerkle = new Merkelizer().run(wrongExecution, code, data, tStorage);
    //   await callback(code, data, tStorage, merkle, challengerMerkle, 'solver');
    // });

    // it('solver has an wrong afterStateRoot at SLOAD', async () => {
    //   const wrongExecution = copy;
    //   // opcode SLOAD
    //   wrongExecution[116].stateRoot = Buffer.alloc(32);
      
    //   const solverMerkle = new Merkelizer().run(wrongExecution, code, data, tStorage);
    //   await callback(code, data, tStorage, solverMerkle, merkle, 'challenger');
    // });

    // it('challenger has an wrong afterStateRoot at SLOAD', async () => {
    //   const wrongExecution = copy;
    //   // opcode SLOAD
    //   wrongExecution[116].stateRoot = Buffer.alloc(32);
      
    //   const challengerMerkle = new Merkelizer().run(wrongExecution, code, data, tStorage);
    //   await callback(code, data, tStorage, merkle, challengerMerkle, 'solver');
    // });

    // it('solver has an output error somewhere in CALLEE step', async () => {
    //   const wrongExecution = copy;
    //   const wrongCalleeStep = calleeCopy;
      
    //   wrongCalleeStep[6].compactStack.push('0x0000000000000000000000000000000000000000000000000000000000000001');
    //   wrongCalleeStep[6].stackHash = '0x0000000000000000000000000000000000000000000000000000000000000001';
    //   wrongExecution[58].calleeSteps[6] = wrongCalleeStep[6];
      
    //   const solverMerkle = new Merkelizer().run(wrongExecution, code, data, tStorage);
    //   await callback(code, data, tStorage, solverMerkle, merkle, 'challenger');
    // });

    // it('challenger has an output error somewhere in CALLEE step', async () => {
    //   const wrongExecution = copy;
    //   const wrongCalleeStep = calleeCopy;
      
    //   wrongCalleeStep[6].compactStack.push('0x0000000000000000000000000000000000000000000000000000000000000001');
    //   wrongCalleeStep[6].stackHash = '0x0000000000000000000000000000000000000000000000000000000000000001';
    //   wrongExecution[58].calleeSteps[6] = wrongCalleeStep[6];
      
    //   const challengerMerkle = new Merkelizer().run(wrongExecution, code, data, tStorage);
    //   await callback(code, data, tStorage, merkle, challengerMerkle, 'solver');
    // });
  });
};
