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
    
    const code = '608060405234801561001057600080fd5b50600436106100365760003560e01c806323188b771461003b5780635745ee731461007f575b600080fd5b61007d6004803603602081101561005157600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff1690602001909291905050506100cb565b005b6100b56004803603604081101561009557600080fd5b81019080803590602001909291908035906020019092919050505061010e565b6040518082815260200191505060405180910390f35b806000806101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffffffffffffff16021790555050565b60008060405180807f6164642875696e743235362c75696e7432353629000000000000000000000000815250601401905060405180910390209050604051818152846004820152836020600483010152602081604483600054617530fa600081141561017957600080fd5b81519350602482016040525050509291505056fea165627a7a72305820eda4c354622c12cb134b1fe2185524ac3319b712dc5b611c977c22842d9fecee0029';
    const data = '0x5745ee7300000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002';
    
    // need to init tStorage
    const tStorage = [
      '0x0000000000000000000000000000000000000000000000000000000000000000',
      '0x08970fed061e7747cd9a38d680a601510cb659fb'.padStart(64,0),
    ];
    
    // callee
    const calleeCode = '6080604052600436106100345760003560e01c80632e52d6061461003657806367e404ce14610061578063771602f7146100b8575b005b34801561004257600080fd5b5061004b610111565b6040518082815260200191505060405180910390f35b34801561006d57600080fd5b50610076610117565b604051808273ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200191505060405180910390f35b3480156100c457600080fd5b506100fb600480360360408110156100db57600080fd5b81019080803590602001909291908035906020019092919050505061013d565b6040518082815260200191505060405180910390f35b60005481565b600160009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1681565b600081830190509291505056fea165627a7a723058203604bd0a2f0841493510a54281376272552d26b588a5e07aff150293aeb124e20029';
    const calleeTstorage = []; 
    
    const accounts = [
        {
          address: web3.utils.toChecksumAddress('5E72914535f202659083Db3a02C984188Fa26e9f'),
          code: code,
          tStorage: tStorage,
          nonce: new BN(0x1, 16),
          balance: new BN(0xa, 16),
          storageRoot: OP.ZERO_HASH,
          codeHash: OP.ZERO_HASH
        },
        // callee
        {
            address: web3.utils.toChecksumAddress('08970FEd061E7747CD9a38d680A601510CB659FB'),
            code: calleeCode,
            tStorage: calleeTstorage,
            nonce: new BN(0x1, 16),
            balance: new BN(0xa, 16),
            storageRoot: OP.ZERO_HASH,
            codeHash: OP.ZERO_HASH
        }
      ];

    let steps;
    let copy;
    let calleeCopy;
    let merkle;
    
    beforeEach(async () => {
      const runtime = new HydratedRuntime();
      steps = await runtime.run({ accounts, code, data, pc: 0, tStorage: tStorage, pc: 0 });
      copy = _.cloneDeep(steps);
      // opcode CALL step
      calleeCopy = _.cloneDeep(steps[117].calleeSteps);
      merkle = new Merkelizer().run(steps, code, data, tStorage);
    });

    it('solver has an wrong stateProof at FirstStep', async () => {
      const wrongExecution = copy;
     
      wrongExecution[0].stateRoot = Buffer.alloc(32);
      wrongExecution[0].calleeAccount.rlpVal = Buffer.alloc(32);
      
      const solverMerkle = new Merkelizer().run(wrongExecution, code, data, tStorage);
      await callback(code, data, tStorage, solverMerkle, merkle, 'challenger');
    });

    it('challenger has an wrong stateProof at FirstStep', async () => {
      const wrongExecution = copy;
     
      wrongExecution[0].stateRoot = Buffer.alloc(32);
      wrongExecution[0].calleeAccount.rlpVal = Buffer.alloc(32);

      const challengerMerkle = new Merkelizer().run(wrongExecution, code, data, tStorage);
      await callback(code, data, tStorage, merkle, challengerMerkle, 'solver');
    });

    it('solver has an wrong stateProof at CALLStart', async () => {
      const wrongExecution = copy;
      const wrongCalleeStep = calleeCopy;

      wrongCalleeStep[0].stateRoot = Buffer.alloc(32);
      wrongCalleeStep[0].calleeAccount.rlpVal = Buffer.alloc(32);
      wrongExecution[117].calleeSteps = wrongCalleeStep;
      const solverMerkle = new Merkelizer().run(wrongExecution, code, data, tStorage);
      await callback(code, data, tStorage, solverMerkle, merkle, 'challenger');
    });

    it('challenger has an wrong stateProof at CALLStart', async () => {
      const wrongExecution = copy;
      const wrongCalleeStep = calleeCopy;

      wrongCalleeStep[0].stateRoot = Buffer.alloc(32);
      wrongCalleeStep[0].calleeAccount.rlpVal = Buffer.alloc(32);
      wrongExecution[117].calleeSteps = wrongCalleeStep;
      const challengerMerkle = new Merkelizer().run(wrongExecution, code, data, tStorage);
      await callback(code, data, tStorage, merkle, challengerMerkle, 'solver');
    });

    it('solver has an wrong stateProof at CALLEnd', async () => {
      const wrongExecution = copy;
      wrongExecution[117].stateRoot = Buffer.alloc(32);
      wrongExecution[117].calleeAccount.rlpVal = Buffer.alloc(32);
      const solverMerkle = new Merkelizer().run(wrongExecution, code, data, tStorage);
      await callback(code, data, tStorage, solverMerkle, merkle, 'challenger');
    });

    it('challenger has an wrong stateProof at CALLEnd', async () => {
      const wrongExecution = copy;
      wrongExecution[117].stateRoot = Buffer.alloc(32);
      wrongExecution[117].calleeAccount.rlpVal = Buffer.alloc(32);
      const challengerMerkle = new Merkelizer().run(wrongExecution, code, data, tStorage);
      await callback(code, data, tStorage, merkle, challengerMerkle, 'solver');
    });

    it('solver first step missing in CALLEE', async () => {
      const wrongExecution = copy;
      const wrongCalleeStep = calleeCopy;

      wrongCalleeStep.shift();
      wrongExecution[117].calleeSteps = wrongCalleeStep;
      const solverMerkle = new Merkelizer().run(wrongExecution, code, data, tStorage);
      await callback(code, data, tStorage, solverMerkle, merkle, 'challenger');
    });    

    it('challenger first step missing in CALLEE', async () => {
      const wrongExecution = copy;
      const wrongCalleeStep = calleeCopy;

      wrongCalleeStep.shift();
      wrongExecution[117].calleeSteps = wrongCalleeStep;
      const challengerMerkle = new Merkelizer().run(wrongExecution, code, data, tStorage);
      await callback(code, data, tStorage, merkle, challengerMerkle, 'solver');
    });

    it('solver has an wrong afterStateRoot at FirstStep', async () => {
      const wrongExecution = copy;
     
      wrongExecution[0].stateRoot = Buffer.alloc(32);
            
      const solverMerkle = new Merkelizer().run(wrongExecution, code, data, tStorage);
      await callback(code, data, tStorage, solverMerkle, merkle, 'challenger');
    });

    it('challenger has an wrong afterStateRoot at FirstStep', async () => {
      const wrongExecution = copy;
     
      wrongExecution[0].stateRoot = Buffer.alloc(32);
     
      const challengerMerkle = new Merkelizer().run(wrongExecution, code, data, tStorage);
      await callback(code, data, tStorage, merkle, challengerMerkle, 'solver');
    });

    it('solver has an wrong afterStateRoot at CALLStart', async () => {
      const wrongExecution = copy;
      const wrongCalleeStep = calleeCopy;

      wrongCalleeStep[0].stateRoot = Buffer.alloc(32);
      wrongExecution[117].calleeSteps = wrongCalleeStep;

      const solverMerkle = new Merkelizer().run(wrongExecution, code, data, tStorage);
      await callback(code, data, tStorage, solverMerkle, merkle, 'challenger');
    });

    it('challenger has an wrong afterStateRoot at CALLStart', async () => {
      const wrongExecution = copy;
      const wrongCalleeStep = calleeCopy;

      wrongCalleeStep[0].stateRoot = Buffer.alloc(32);
      wrongExecution[117].calleeSteps = wrongCalleeStep;
      
      const challengerMerkle = new Merkelizer().run(wrongExecution, code, data, tStorage);
      await callback(code, data, tStorage, merkle, challengerMerkle, 'solver');
    });

    it('solver has an wrong afterStateRoot at CALLEnd', async () => {
      const wrongExecution = copy;
      
      wrongExecution[117].stateRoot = Buffer.alloc(32);
      wrongExecution[117].calleeAccount.rlpVal = Buffer.alloc(32);
      
      const solverMerkle = new Merkelizer().run(wrongExecution, code, data, tStorage);
      await callback(code, data, tStorage, solverMerkle, merkle, 'challenger');
    });

    it('challenger has an wrong afterStateRoot at CALLEnd', async () => {
      const wrongExecution = copy;
      
      wrongExecution[117].stateRoot = Buffer.alloc(32);
      wrongExecution[117].calleeAccount.rlpVal = Buffer.alloc(32);
      
      const challengerMerkle = new Merkelizer().run(wrongExecution, code, data, tStorage);
      await callback(code, data, tStorage, merkle, challengerMerkle, 'solver');
    });

    it('solver has an output error somewhere in CALLEE step', async () => {
      const wrongExecution = copy;
      const wrongCalleeStep = calleeCopy;
      
      wrongCalleeStep[6].compactStack.push('0x0000000000000000000000000000000000000000000000000000000000000001');
      wrongCalleeStep[6].stackHash = '0x0000000000000000000000000000000000000000000000000000000000000001';
      wrongExecution[117].calleeSteps = wrongCalleeStep;
      
      const solverMerkle = new Merkelizer().run(wrongExecution, code, data, tStorage);
      await callback(code, data, tStorage, solverMerkle, merkle, 'challenger');
    });

    it('challenger has an output error somewhere in CALLEE step', async () => {
      const wrongExecution = copy;
      const wrongCalleeStep = calleeCopy;
      
      wrongCalleeStep[6].compactStack.push('0x0000000000000000000000000000000000000000000000000000000000000001');
      wrongCalleeStep[6].stackHash = '0x0000000000000000000000000000000000000000000000000000000000000001';
      wrongExecution[117].calleeSteps = wrongCalleeStep;
      
      const challengerMerkle = new Merkelizer().run(wrongExecution, code, data, tStorage);
      await callback(code, data, tStorage, merkle, challengerMerkle, 'solver');
    });
  });
};
