# IT 505 · Class 4 · Lesson 4 · Example 4 — "Do you need a blockchain?" as a function, applied to three Mercadillo 505 proposals.
# Task: the management of Mercadillo 505 received three proposals that all say "blockchain"; we answer six yes/no questions for each.
# Link to the lecture: the decision flowchart of Wüst and Gervais (2018, CC BY), adapted; public, private and permissioned ledgers.
# Run it with:  python l4_do_you_need_a_blockchain.py   (standard library only)

# The six questions, in the order of the flowchart; each one is asked only if the previous answers lead to it.
QUESTIONS = {
    # Q1: is there data that must be kept and updated over time (a "state"), such as balances or delivery records?
    "state": "Q1 Do you need to store data that changes over time?",
    # Q2: will more than one party add or change records?
    "writers": "Q2 Are there several parties who write records?",
    # Q3: is there someone all writers accept as the keeper of the records, and who is always reachable?
    "ttp": "Q3 Can you use an always-online trusted third party?",
    # Q4: is every writer identified in advance (by contract, by registration)?
    "known": "Q4 Are all writers known?",
    # Q5: do all writers trust each other not to cheat?
    "trusted": "Q5 Are all writers trusted?",
    # Q6: must people outside the group be able to check the records themselves?
    "public": "Q6 Is public verifiability required?",
}


# decide walks the flowchart for one proposal and returns the list of answered questions and the verdict.
def decide(answers):
    # path records every question asked, with its yes/no answer, so we can explain the verdict.
    path = []
    # ask is a small helper: it records the question and returns the answer given in the dictionary.
    def ask(key):
        # The answer for this question, True (yes) or False (no).
        value = answers[key]
        # We keep the question text and the answer for the printout.
        path.append((QUESTIONS[key], "yes" if value else "no"))
        # The caller uses the answer to choose the next branch.
        return value
    # Without data to keep there is nothing to store, in a blockchain or anywhere else.
    if not ask("state"):
        # Verdict when Q1 is "no".
        return path, "No blockchain: nothing needs to be stored"
    # One single writer can simply use its own database.
    if not ask("writers"):
        # Verdict when Q2 is "no".
        return path, "No blockchain: use a database (for example PostgreSQL)"
    # A keeper that everybody accepts can run an ordinary database for everyone.
    if ask("ttp"):
        # Verdict when Q3 is "yes".
        return path, "No blockchain: the trusted third party runs a database"
    # Unknown writers (anyone may join) need an open network: Bitcoin and Ethereum are examples.
    if not ask("known"):
        # Verdict when Q4 is "no".
        return path, "Permissionless (public) blockchain"
    # Known writers who all trust each other can share a database with access rights.
    if ask("trusted"):
        # Verdict when Q5 is "yes".
        return path, "No blockchain: a shared database with access control is enough"
    # The last question decides who may read and check the records.
    if ask("public"):
        # Verdict when Q6 is "yes".
        return path, "Public permissioned blockchain (known writers, anyone may verify)"
    # Verdict when Q6 is "no".
    return path, "Private permissioned blockchain (known writers, members verify)"


# PROPOSALS are the three ideas management received; each answer is a decision the business makes, not a technical fact.
PROPOSALS = {
    # Proposal 1: loyalty points; only Mercadillo 505's own system adds and spends points.
    "1 Loyalty points on a blockchain": {"state": True, "writers": False, "ttp": True, "known": True, "trusted": True, "public": False},
    # Proposal 2: hand-over records between Mercadillo 505, 40 producers and two courier companies, with no keeper all accept.
    "2 Shared delivery hand-over log": {"state": True, "writers": True, "ttp": False, "known": True, "trusted": False, "public": False},
    # Proposal 3: origin certificates for olive oil written by registered producers; any shopper must be able to check them.
    "3 Origin certificates shoppers can check": {"state": True, "writers": True, "ttp": False, "known": True, "trusted": False, "public": True},
}

# The main block runs only when the file is started directly.
if __name__ == "__main__":
    # We evaluate every proposal in turn.
    for name, answers in PROPOSALS.items():
        # decide returns the questions asked and the verdict.
        path, verdict = decide(answers)
        # A heading line for the proposal.
        print("== Proposal", name)
        # Every question that was asked, with its answer.
        for question, answer in path:
            # Indented so that the path is easy to read.
            print("   ", question, "->", answer)
        # The verdict closes the proposal.
        print("    VERDICT:", verdict)
