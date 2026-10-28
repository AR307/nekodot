import type { RpcError } from '@nekodot/protocol';

export class NodeFault extends Error {
  constructor(
    readonly code: RpcError['code'],
    message: string,
  ) {
    super(message);
  }
}
