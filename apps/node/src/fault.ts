export class NodeFault extends Error {
  constructor(
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}
