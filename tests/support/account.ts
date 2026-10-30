import { hash, argon2id } from 'argon2';
import type { RelayDatabase } from '../../apps/relay/src/database';

/** Focused routing tests start from an already verified account; signup has its own SMTP journey. */
export async function seedVerifiedAccount(
  database: RelayDatabase,
  email: string,
  password: string,
) {
  const id = database.createUser(email, await hash(password, { type: argon2id }));
  database.verifyEmail(id);
  return id;
}
