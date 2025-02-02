import { Blockchain, SandboxContract, TreasuryContract } from '@ton/sandbox';
import { beginCell, Cell, toNano } from '@ton/core';
import { Proxy } from '../wrappers/Proxy';
import '@ton/test-utils';
import { compile } from '@ton/blueprint';

describe('Proxy', () => {
    let code: Cell;

    beforeAll(async () => {
        code = await compile('Proxy');
    });

    let blockchain: Blockchain;
    let deployer: SandboxContract<TreasuryContract>;
    let proxy: SandboxContract<Proxy>;

    beforeEach(async () => {
        blockchain = await Blockchain.create();
        const owner = await blockchain.treasury('owner')

        proxy = blockchain.openContract(Proxy.createFromConfig({
            ownerAddress: owner.address,
        }, code));

        deployer = await blockchain.treasury('deployer');

        const deployResult = await proxy.sendDeploy(deployer.getSender(), toNano('0.05'));

        expect(deployResult.transactions).toHaveTransaction({
            from: deployer.address,
            to: proxy.address,
            deploy: true,
        });
    });

    it('trx to proxy from owner', async () => {
        const owner = await blockchain.treasury( 'owner')
        const someone1 = await blockchain.treasury( 'someone1')
        const transaction = await deployer.send({
            to: proxy.address,
            value: toNano('1'),
            body: beginCell()
                .storeUint(0x5eb9a301, 32) // op
                .storeUint(0, 64) // queryId
                .storeAddress(someone1.address)
                .storeCoins(toNano('0.9'))
                .endCell()
        })

        expect(transaction.transactions).toHaveTransaction({
            from: proxy.address,
            to: owner.address,
            success: true
        });
    });

    it('trx to proxy from someone', async () => {
        const owner = await blockchain.treasury( 'owner')
        const someone = await blockchain.treasury( 'someone')
        const transaction = await someone.send({
            to: proxy.address,
            value: toNano('1'),
        })

        expect(transaction.transactions).toHaveTransaction({
            from: someone.address,
            to: proxy.address,
            success: true
        });

        expect(transaction.transactions).toHaveTransaction({
            from: proxy.address,
            to: owner.address,
            success: true
        });
    });
});
