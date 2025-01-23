import {
    Address,
    beginCell,
    Builder,
    Cell,
    Contract,
    contractAddress,
    ContractProvider,
    Sender,
    SendMode
} from '@ton/core';

export type SimpleCounterConfig = {
    owner: Address;
    counter: number;
};

export function simpleCounterConfigToCell(config: SimpleCounterConfig): Cell {
    return beginCell()
        .storeAddress(config.owner)
        .storeUint(config.counter, 32)
    .endCell();
}

export function storeOpResetCounter() {
    return (builder: Builder) => {
        builder.storeUint(0x3dc2af2d, 32);
    };
}

export class SimpleCounter implements Contract {
    constructor(readonly address: Address, readonly init?: { code: Cell; data: Cell }) {}

    static createFromAddress(address: Address) {
        return new SimpleCounter(address);
    }

    static createFromConfig(config: SimpleCounterConfig, code: Cell, workchain = 0) {
        const data = simpleCounterConfigToCell(config);
        const init = { code, data };
        return new SimpleCounter(contractAddress(workchain, init), init);
    }

    async sendDeploy(provider: ContractProvider, via: Sender, value: bigint) {
        await provider.internal(via, {
            value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: beginCell().endCell(),
        });
    }

    async getCounter(provider: ContractProvider) {
        let { stack } = await provider.get('counter', []);
        return stack.readNumber();
    }

    async getOwner(provider: ContractProvider) {
        let { stack } = await provider.get('owner', []);
        return stack.readAddress();
    }
}
