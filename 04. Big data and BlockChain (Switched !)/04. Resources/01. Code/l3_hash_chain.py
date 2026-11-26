# IT 505 · Class 4 · Lesson 3 · Example 3 — A tamper-evident order log: every record carries the hash of the record before it.
# Task: Mercadillo 505's accounting team wants to prove that no old order was changed after the payout to the sellers.
# Link to the lecture: hash (SHA-256), block, chain, and why a change in one old block breaks every block after it.
# Run it with:  python l3_hash_chain.py   (standard library only)

# hashlib is Python's standard library module for hash functions such as SHA-256.
import hashlib

# GENESIS is the "previous hash" of the very first block: 64 zeros, because nothing comes before it.
GENESIS = "0" * 64

# ORDERS are six order records of Saturday 21 November 2026 (fictional data), written as one line of text each.
ORDERS = [
    # Each text keeps the fields in a fixed order: order id, date, customer code, product, quantity, amount.
    # A customer code (C-017) is used instead of a name: personal data should stay out of an append-only log.
    "M505-1041|2026-11-21|C-017|Manchego cheese, 250 g|2|14.80",
    # The second record of the day.
    "M505-1042|2026-11-21|C-102|Extra virgin olive oil, 1 L|1|9.80",
    # The third record: this is the line someone will try to change later.
    "M505-1043|2026-11-21|C-044|Turrón de Jijona, 300 g|2|17.00",
    # The fourth record.
    "M505-1044|2026-11-21|C-131|Rioja red wine, 75 cl|3|34.50",
    # The fifth record.
    "M505-1045|2026-11-21|C-009|Saffron threads, 1 g|2|13.80",
    # The sixth record.
    "M505-1046|2026-11-21|C-076|Bomba rice, 1 kg|1|4.40",
]


# sha256_hex computes the SHA-256 hash of a text and returns it as 64 hexadecimal characters (256 bits).
def sha256_hex(text):
    # encode("utf-8") turns the text into bytes, hexdigest() turns the 32-byte result into readable hexadecimal.
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


# build_chain turns the list of records into a list of blocks; each block stores its record, the previous hash and its own hash.
def build_chain(records):
    # chain starts empty and grows by one block per record.
    chain = []
    # The first block points to GENESIS.
    prev = GENESIS
    # enumerate numbers the records from 1, so that the blocks are called 1, 2, 3 ...
    for number, record in enumerate(records, 1):
        # The hash covers the previous hash AND the record: changing either one changes this hash.
        h = sha256_hex(prev + "|" + record)
        # The block is a small dictionary with the four things we need to check it later.
        chain.append({"block": number, "record": record, "prev_hash": prev, "hash": h})
        # The hash of this block becomes the "previous hash" of the next block: this is the chain.
        prev = h
    # The finished chain is returned to the caller.
    return chain


# verify recomputes every hash and reports the first block where the stored values no longer match.
def verify(chain):
    # expected_prev is what the next block must point to; at the start it is GENESIS.
    expected_prev = GENESIS
    # We check the blocks in order, from the oldest to the newest.
    for b in chain:
        # Check 1: does the block point to the real hash of the block before it?
        if b["prev_hash"] != expected_prev:
            # The link is broken: the block before was changed (and re-hashed) after this block was written.
            return "BROKEN at block %d: prev_hash does not match the hash of block %d" % (b["block"], b["block"] - 1)
        # Check 2: does the stored hash still match the record and the previous hash?
        if sha256_hex(b["prev_hash"] + "|" + b["record"]) != b["hash"]:
            # The record was changed after its hash was written.
            return "BROKEN at block %d: the record does not match its hash" % b["block"]
        # The block is valid; the next block must point to this block's hash.
        expected_prev = b["hash"]
    # Every block passed both checks.
    return "VALID: %d blocks, every link checked" % len(chain)


# The main block runs only when the file is started directly.
if __name__ == "__main__":
    # Build the chain from the six records.
    chain = build_chain(ORDERS)
    # Print each block with the first 12 characters of its hashes (the full hash has 64).
    for b in chain:
        # "%-10s" pads the order id to 10 characters, so that the columns line up.
        print("block %d  %-10s prev=%s…  hash=%s…" % (b["block"], b["record"][:9], b["prev_hash"][:12], b["hash"][:12]))
    # First check: nothing was changed yet.
    print("check 1:", verify(chain))
    # Two texts that differ by one letter have completely different hashes (the avalanche effect).
    print("sha256('Madrid') =", sha256_hex("Madrid")[:16] + "…", " sha256('madrid') =", sha256_hex("madrid")[:16] + "…")
    # Tampering, case A: someone changes the quantity of order M505-1043 from 2 to 1 (and the amount to 8.50) in block 3.
    chain[2]["record"] = chain[2]["record"].replace("|2|17.00", "|1|8.50")
    # The stored hash of block 3 was not updated, so the record and its hash disagree.
    print("check 2 (block 3 edited):", verify(chain))
    # Tampering, case B: the person also recomputes the hash of block 3 to hide the change.
    chain[2]["hash"] = sha256_hex(chain[2]["prev_hash"] + "|" + chain[2]["record"])
    # Now block 3 looks valid on its own, but block 4 still points to the OLD hash of block 3.
    print("check 3 (block 3 re-hashed):", verify(chain))
    # To hide the change completely, every later block would have to be re-hashed too; we count how many.
    print("blocks to rewrite to hide the change:", len(chain) - 2)
