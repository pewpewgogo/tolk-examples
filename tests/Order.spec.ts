import { Blockchain, SandboxContract, TreasuryContract } from '@ton/sandbox';
import { beginCell, Cell, toNano } from '@ton/core';
import '@ton/test-utils';
import { compile } from '@ton/blueprint';
import { Order } from '../wrappers/Order';

describe('Order', () => {
    let code: Cell;

    beforeAll(async () => {
        code = await compile('Order');
    });

    let blockchain: Blockchain;
    let deployer: SandboxContract<TreasuryContract>;
    let order: SandboxContract<Order>;

    beforeEach(async () => {
        blockchain = await Blockchain.create();
        const owner = await blockchain.treasury('owner')

        order = blockchain.openContract(Order.createFromConfig({
            ctxCompleteState: false,
            ctxAmountTokenA: toNano(100),
            ctxAmountTokenB: toNano(200),
            ctxOrderOwner: owner.address,
            ctxTokenA: new Cell(),
            ctxTokenB: new Cell()
        }, code));

        deployer = await blockchain.treasury('deployer');

        const deployResult = await order.sendDeploy(deployer.getSender(), toNano('0.1'));

        expect(deployResult.transactions).toHaveTransaction({
            from: deployer.address,
            to: order.address,
            deploy: true,
        });
    });

    it('trx to proxy from owner', async () => {
        const owner = await blockchain.treasury( 'owner')
        const someone1 = await blockchain.treasury( 'someone1')
        const transaction = await deployer.send({
            to: order.address,
            value: toNano('1'),
            body: beginCell()
                .storeUint(0x5eb9a301, 32) // op
                .storeUint(0, 64) // queryId
                .storeAddress(someone1.address)
                .storeCoins(toNano('0.9'))
                .endCell()
        })

        expect(transaction.transactions).toHaveTransaction({
            from: order.address,
            to: owner.address,
            success: true
        });
    });
});
