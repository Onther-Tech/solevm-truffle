'use strict';

const VM = require('ethereumjs-vm');
const utils = require('ethereumjs-util');
const BN = utils.BN;

const OP = require('./constants');
const OPCODES = require('./Opcodes');

const HexaryTrie = require('./HexaryTrie');

const PRECOMPILED = {
  '1': require('./precompiled/01-ecrecover.js'),
  '2': require('./precompiled/02-sha256.js'),
  '3': require('./precompiled/03-ripemd160.js'),
  '4': require('./precompiled/04-identity.js'),
  '5': require('./precompiled/05-modexp.js'),
  '6': require('./precompiled/06-ecadd.js'),
  '7': require('./precompiled/07-ecmul.js'),
  '8': require('./precompiled/08-ecpairing.js'),
};

const ERRNO_MAP =
  {
    'stack overflow': 0x01,
    'stack underflow': 0x02,
    'invalid opcode': 0x04,
    'invalid JUMP': 0x05,
    'instruction not supported': 0x06,
    'revert': 0x07,
    'static state change': 0x0b,
    'out of gas': 0x0d,
    'internal error': 0xff,
  };

const ERROR = {
  OUT_OF_GAS: 'out of gas',
  STACK_UNDERFLOW: 'stack underflow',
  STACK_OVERFLOW: 'stack overflow',
  INVALID_JUMP: 'invalid JUMP',
  INSTRUCTION_NOT_SUPPORTED: 'instruction not supported',
  INVALID_OPCODE: 'invalid opcode',
  REVERT: 'revert',
  STATIC_STATE_CHANGE: 'static state change',
  INTERNAL_ERROR: 'internal error',
};

function VmError (error) {
  this.error = error;
  this.errorType = 'VmError';
};

const DEFAULT_CONTRACT_ADDRESS = Buffer.from('0f572e5295c57F15886F9b263E2f6d2d6c7b5ec6', 'hex');
const DEFAULT_CALLER = Buffer.from('CA35b7d915458EF540aDe6068dFe2F44E8fa733c', 'hex');

// 256x32 bytes
const MAX_MEM_WORD_COUNT = new BN(256);

function NumToBuf32 (val) {
  val = val.toString(16);

  while (val.length !== 64) {
    val = '0' + val;
  }

  return Buffer.from(val, 'hex');
}

function NumToHex (val) {
  val = val.toString(16).replace('0x', '');

  if (val.length % 2 !== 0) {
    val = '0' + val;
  }

  return val;
}

// Find Ceil(`this` / `num`)
function divCeil (a, b) {
  const div = a.div(b);
  const mod = a.mod(b);

  // Fast case - exact division
  if (mod.isZero()) {
    return div;
  }

  // Round up
  return div.isNeg() ? div.isubn(1) : div.iaddn(1);
}

module.exports = class EVMRuntime extends VM.MetaVM {
  constructor () {
    super({ hardfork: 'petersburg' });
  }

  async initHexaryTrie (accounts) {
    const self = this;

    return new Promise(async (resolve, reject) => {
      let len = accounts.length;
      
      self.accounts = [];
      
      for (let i = 0; i < len; i++) {
        let obj = accounts[i];
        let account = {};
        account.address = obj.address;
        account.storageTrie = new HexaryTrie();
        account.tStorage = obj.tStorage;
                
        let proof = [];
        if (obj.tStorage) {
          let storageLen = obj.tStorage.length;

          // TODO: need to fix sync to be complete?
          for (let i = 0; i < storageLen - 1; i++) {
            if (i % 2 === 0) {
                let key = obj.tStorage[i].replace('0x', '');
                let val = obj.tStorage[i+1].replace('0x', '');
                
                await account.storageTrie.putData(key, val);
                const data = await account.storageTrie.getData(key);
                // console.log('111key', key);
                // console.log('111val', val);
                // console.log('111data', data);
                
            }
          }
                  
          for (let i = 0; i < storageLen - 1; i++) {
            if (i % 2 === 0) {
                let elem = {};
                let key = obj.tStorage[i].replace('0x', '');
                const {rootHash, hashedKey, stack} = await account.storageTrie.getProof(key);
                // console.log('222key', key);
                // console.log('222rootHash', rootHash);
                // console.log('222hashedKey', hashedKey);
                // console.log('222stack', stack);

                elem.key = key;
                elem.rootHash = rootHash;
                elem.hashedKey = hashedKey;
                elem.stack = stack;
                proof.push(elem);
            }
          }
        }
        const storageHash = account.storageTrie.trie.root;
        account.storageHash = '0x' + storageHash.toString('hex');
        account.initStorageProof = proof;
        self.accounts.push(account);
       }
       
      //  console.log('initHexaryTrie', this.accounts)
       resolve();
    })
  }

  async initAccounts (accounts) {
    const self = this;

    return new Promise(async (resolve, reject) => {
      let openCallbacks = 0;

      function resolveCallbacks () {
        if (--openCallbacks === 0) {
          resolve(openCallbacks);
        }
      }

      async function setStorage(addr, address, value) {
        return new Promise((resolve, reject) => {
          const cb = function (err, result) {
            if (err) {
              reject(err)
              return;
            }
            resolve();
        };
        
        self.stateManager.putContractStorage(
          addr,
          NumToBuf32(address),
          NumToBuf32(value | 0),
          cb
        );  

        return;
              
        });
      }
      
      let len = accounts.length;
   
      while (len--) {
        let obj = accounts[len];
        let addr = Buffer.isBuffer(obj.address)
          ? obj.address : Buffer.from((obj.address || '').replace('0x', ''), 'hex');
        let account = new VM.deps.Account();
        account.balance = obj.balance | 0;
       
        // resolves immediately
        self.stateManager.putAccount(addr, account, () => {});

        if (obj.tStorage) {
          let storageLen = obj.tStorage.length;
         
            for (let i = 0; i < storageLen - 1; i++) {
              if (i % 2 === 0) {
                  let address = obj.tStorage[i].replace('0x', '');
                  let value = obj.tStorage[i+1].replace('0x', '');
                  address = new BN(address, 16);
                  value = new BN(value, 16);
                  
                  await setStorage(addr, address, value);
              }
            }
        }
        
        if (obj.code) {
          openCallbacks++;
          self.stateManager.putContractCode(addr, Buffer.from(obj.code, 'hex'), resolveCallbacks);
        }
      }
      
      if (openCallbacks === 0) {
        resolve();
      }
    });
  }

  async runNextStep (runState) {
    if (runState.depth !== 0) {
      // throw is expected on errors. That's ok
      await super.runNextStep(runState);
      return;
    }

    let exceptionError;
    try {
      await super.runNextStep(runState);
    } catch (e) {
      exceptionError = e;
    }

    let errno = 0;
    if (exceptionError) {
      errno = ERRNO_MAP[exceptionError.error] || 0xff;
      runState.vmError = true;
    }

    if (runState.memoryWordCount.gt(MAX_MEM_WORD_COUNT)) {
      runState.vmError = true;
      errno = OP.ERROR_INTERNAL;
    }

    runState.errno = errno;
  }

  async initRunState (obj) {
    const self = this;
    const runState = await super.initRunState(obj);

    runState.errno = 0;
    
    if (obj.stack) {
      const len = obj.stack.length;

      for (let i = 0; i < len; i++) {
        runState.stack.push(new BN(obj.stack[i].replace('0x', ''), 'hex'));
      }
    }

    if (obj.mem) {
      const len = obj.mem.length;

      for (let i = 0; i < len; i++) {
        const memSlot = obj.mem[i];

        runState.memoryWordCount.iaddn(1);

        for (let x = 2; x < 66;) {
          const hexVal = memSlot.substring(x, x += 2);

          runState.memory.push(hexVal ? parseInt(hexVal, 16) : 0);
        }
      }

      const words = runState.memoryWordCount;
      // words * 3 + words ^2 / 512
      runState.highestMemCost = words.muln(3).add(words.mul(words).divn(512));
    }

    if (typeof obj.gasRemaining !== 'undefined') {
      runState.gasLeft = new BN(Buffer.from(NumToHex(obj.gasRemaining), 'hex'));
    }
    
    return runState;
  }

  async run ({ accounts, code, data, stack, mem, tStorage, gasLimit, gasRemaining, pc, stepCount }) {
    data = data || '0x';
        
    if (Array.isArray(code)) {
      code = code.join('');
    } else {
      // should be a (hex) string
      code = code.replace('0x', '');
    }

    // @dev if not set account, set default account
    if (!accounts) {

      accounts = [
        {
          address: OP.DEFAULT_CONTRACT_ADDRESS,
          code: code,
          tStorage: tStorage
        }
      ];
    }
    
    // TODO: make it configurable by the user
    // @dev it should be needed to input externally because of we don't have local DB yet.
    // init default account
    // input - [address, code, tStorage]
    await this.initAccounts(accounts);
    // commit to the tree, needs a checkpoint first 🤪
    await new Promise((resolve) => {
      this.stateManager.checkpoint(() => {
        this.stateManager.commit(() => {
          resolve();
        });
      });
    });

    await this.initHexaryTrie(accounts);
       
    // TODO: Support EVMParameters
    const runState = await this.initRunState({
      code: Buffer.from(code, 'hex'),
      data: Buffer.from(data.replace('0x', ''), 'hex'),
      gasLimit: Buffer.from(NumToHex(gasLimit || OP.BLOCK_GAS_LIMIT), 'hex'),
      caller: DEFAULT_CALLER,
      origin: DEFAULT_CALLER,
      address: DEFAULT_CONTRACT_ADDRESS,
      pc: pc | 0,
      mem,
      stack,
      tStorage: tStorage,
      gasRemaining
    });
    
    stepCount = stepCount | 0;

    await super.run(runState, stepCount);

    return runState;
  }
};
