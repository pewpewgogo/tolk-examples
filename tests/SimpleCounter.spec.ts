import { Blockchain, SandboxContract, TreasuryContract } from '@ton/sandbox';
import { beginCell, Cell, toNano } from '@ton/core';
import { SimpleCounter, storeOpResetCounter } from '../wrappers/SimpleCounter';
import '@ton/test-utils';
import { compile } from '@ton/blueprint';

describe('SimpleCounter', () => {
    let code: Cell;

    beforeAll(async () => {
        code = await compile('SimpleCounter');
    });

    let blockchain: Blockchain;
    let deployer: SandboxContract<TreasuryContract>;
    let owner: SandboxContract<TreasuryContract>;
    let simpleCounter: SandboxContract<SimpleCounter>;

    beforeEach(async () => {
        blockchain = await Blockchain.create();
        owner = await blockchain.treasury('owner');
        simpleCounter = blockchain.openContract(SimpleCounter.createFromConfig({
            owner: owner.address,
            counter: 0,
        }, code));
        deployer = await blockchain.treasury('deployer');

        const deployResult = await simpleCounter.sendDeploy(deployer.getSender(), toNano('0.05'));

        expect(deployResult.transactions).toHaveTransaction({
            from: deployer.address,
            to: simpleCounter.address,
            deploy: true,
            success: true,
        });

        const contractOwner = await simpleCounter.getOwner();
        expect(contractOwner).toEqualAddress(owner.address);

        const currentCounter = await simpleCounter.getCounter();
        expect(currentCounter).toEqual(1); // here is 1 because of the deploy transaction above incrementing the counter
    });

    it('should increment by owner', async () => {
        const transaction = await owner.send({
            to: simpleCounter.address,
            value: toNano('0.1'),
        });

        expect(transaction.transactions).toHaveTransaction({
            from: owner.address,
            to: simpleCounter.address,
            success: true
        });

        const contractCounterValue = await simpleCounter.getCounter()
        expect(contractCounterValue).toEqual(2);
    });

    it('should be reset by owner', async () => {
        const transaction = await owner.send({
            to: simpleCounter.address,
            value: toNano('0.1'),
            body: beginCell()
                .store(storeOpResetCounter())
                .endCell(),
        });

        expect(transaction.transactions).toHaveTransaction({
            from: owner.address,
            to: simpleCounter.address,
            success: true
        });

        const contractCounterValue = await simpleCounter.getCounter()
        expect(contractCounterValue).toEqual(0); // deploy transaction + reset transaction
    });

    it('should increment by random user', async () => {
        const randomUser = await blockchain.treasury('randomUser');
        const randomUser2 = await blockchain.treasury('randomUser2');
        const transaction = await randomUser.send({
            to: simpleCounter.address,
            value: toNano('0.1'),
        });

        const transaction2 = await randomUser2.send({
            to: simpleCounter.address,
            value: toNano('0.1'),
        });

        expect(transaction.transactions).toHaveTransaction({
            from: randomUser.address,
            to: simpleCounter.address,
        });

         expect(transaction2.transactions).toHaveTransaction({
            from: randomUser2.address,
            to: simpleCounter.address,
        });

        const contractCounterValue = await simpleCounter.getCounter()
        expect(contractCounterValue).toEqual(3); // deploy transaction + 2 increment transactions
    });
});
