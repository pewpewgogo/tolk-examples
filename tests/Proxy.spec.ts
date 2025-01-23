import { Blockchain, SandboxContract, TreasuryContract } from '@ton/sandbox';
import { Cell, toNano } from '@ton/core';
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
            success: true,
        });
    });

    it('trx to proxy', async () => {
        const owner = await blockchain.treasury( 'owner')
        const transaction = await deployer.send({
            to: proxy.address,
            value: toNano('1'),
        })

        expect(transaction.transactions).toHaveTransaction({
            from: proxy.address,
            to: owner.address,
        });
    });
});
