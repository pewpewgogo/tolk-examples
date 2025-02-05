import { Address, beginCell, Cell, Contract, contractAddress, ContractProvider, Sender, SendMode, toNano } from '@ton/core';

export type OrderConfig = {
    ctxCompleteState: boolean
    ctxAmountTokenA: bigint
    ctxAmountTokenB: bigint
    ctxOrderOwner: Address
    ctxTokenA: Cell
    ctxTokenB: Cell
};

export function OrderConfigToCell(config: OrderConfig): Cell {
    return beginCell()
        .storeInt(config.ctxCompleteState ? -1 : 0, 1)
        .storeCoins(config.ctxAmountTokenA)
        .storeCoins(config.ctxAmountTokenB)
        .storeAddress(config.ctxOrderOwner)
        .storeRef(config.ctxTokenA)
        .storeRef(config.ctxTokenB)
        .endCell();
}

export class Order implements Contract {
    constructor(readonly address: Address, readonly init?: { code: Cell; data: Cell }) {}

    static createFromAddress(address: Address) {
        return new Order(address);
    }

    static createFromConfig(config: OrderConfig, code: Cell, workchain = 0) {
        const data = OrderConfigToCell(config);
        const init = { code, data };
        return new Order(contractAddress(workchain, init), init);
    }

    async sendDeploy(provider: ContractProvider, via: Sender, value: bigint) {
        await provider.internal(via, {
            value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: beginCell().endCell(),
        });
    }
}
