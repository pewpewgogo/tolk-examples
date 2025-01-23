import { toNano } from '@ton/core';
import { SimpleCounter } from '../wrappers/SimpleCounter';
import { compile, NetworkProvider } from '@ton/blueprint';

export async function run(provider: NetworkProvider) {
    const simpleCounter = provider.open(SimpleCounter.createFromConfig({}, await compile('SimpleCounter')));

    await simpleCounter.sendDeploy(provider.sender(), toNano('0.05'));

    await provider.waitForDeploy(simpleCounter.address);

    // run methods on `simpleCounter`
}
