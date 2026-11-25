# IT 505 · Class 3 · Example 1 — from business rules to an inventory of entities and relationships. Educational material — Cyber.SoHo / Asen Grozdanov. Fictional data (Mercadillo 505).
# Run:  python3 rules_to_inventory.py     (Python 3.9 or later; nothing to install)

# The module re provides regular expressions: patterns that describe the form a text must have.
import re

# The notes taken while interviewing the owner of Mercadillo 505: eight sentences in one Python list.
SENTENCES = [
    # Sentence 1 reads the link between customer and order from the side of the customer.
    "A customer places zero or more orders.",
    # Sentence 2 reads the same link from the side of the order.
    "An order belongs to exactly one customer.",
    # Sentence 3 reads the link between order and product from the side of the order.
    "An order contains one or more products.",
    # Sentence 4 reads the same link from the side of the product.
    "A product appears in zero or more orders.",
    # Sentence 5 restricts the values of one attribute: no two customers may share an e-mail address.
    "Two customers cannot have the same e-mail address.",
    # Sentence 6 restricts another value: a quantity below one makes no sense.
    "The quantity of a product in an order must be greater than zero.",
    # Sentence 7 names two things but does not say how many of one belong to the other.
    "An order has products.",
    # Sentence 8 is an opinion about the service; it says nothing about the data.
    "Customers like fast delivery.",
# The square bracket closes the list.
]

# The four accepted wordings of "how many", each with its minimum and its maximum.
HOW_MANY = {
    # Exactly one: at least 1 and at most 1.
    "exactly one": (1, 1),
    # Zero or one: optional, and never more than 1.
    "zero or one": (0, 1),
    # Zero or more: optional, with no upper limit.
    "zero or more": (0, "many"),
    # One or more: at least 1, with no upper limit.
    "one or more": (1, "many"),
# The brace closes the dictionary.
}

# The form of a relationship rule, written as one pattern in four pieces; re.compile prepares it for repeated use.
RELATIONSHIP = re.compile(
    # Piece 1: the article "A" or "An", then the name of the first entity in lower-case letters.
    r"^An? (?P<first>[a-z ]+?) "
    # Piece 2: one of the five verbs that the interviewer agreed to use.
    r"(?P<verb>places|belongs to|contains|refers to|appears in) "
    # Piece 3: one of the four wordings of "how many".
    r"(?P<how_many>exactly one|zero or one|zero or more|one or more) "
    # Piece 4: the second entity, an optional plural s, and the full stop that ends the sentence.
    r"(?P<second>[a-z ]+?)s?\.$"
# The parenthesis closes the call of re.compile.
)
# The form of a value rule: the sentence contains the word must or the word cannot.
VALUE = re.compile(r"\b(must|cannot)\b")

# An empty list that will receive the five parts of every relationship rule.
relationship_rules = []
# An empty list that will receive every entity name once, in the order of first appearance.
entities = []
# Read the sentences one by one; enumerate also gives the number of the sentence, starting at 1.
for number, sentence in enumerate(SENTENCES, start=1):
    # Compare the sentence with the form of a relationship rule; the result is None when it does not fit.
    found = RELATIONSHIP.match(sentence)
    # First case: the sentence is a relationship rule.
    if found:
        # Translate the wording, for example "zero or more", into the pair (0, "many").
        minimum, maximum = HOW_MANY[found["how_many"]]
        # Keep the five parts of the rule together as one tuple.
        relationship_rules.append((found["first"], found["verb"], minimum, maximum, found["second"]))
        # Look at the two entity names of the rule.
        for name in (found["first"], found["second"]):
            # Add a name to the inventory only the first time it is met.
            if name not in entities:
                # The method append puts the new name at the end of the list.
                entities.append(name)
        # Print the rule in a fixed layout: ENTITY --verb (minimum..maximum)--> ENTITY.
        print(f"{number}. RELATIONSHIP RULE  {found['first'].upper()} --{found['verb']} ({minimum}..{maximum})--> {found['second'].upper()}")
    # Second case: the sentence restricts a value; it is kept for Class 4, where it becomes a constraint.
    elif VALUE.search(sentence):
        # Print the value rule unchanged.
        print(f"{number}. VALUE RULE         {sentence}")
    # Third case: the sentence has neither form, so the analyst must go back to the owner.
    else:
        # Print the sentence with a clear label.
        print(f"{number}. NOT A RULE YET     {sentence}")

# The inventory for the conceptual model: every entity once, in capital letters.
print("Entities:", ", ".join(name.upper() for name in entities))
# A dictionary that will collect, for every pair of entities, the maximum read from each side.
pairs = {}
# Go through the relationship rules again.
for first, verb, minimum, maximum, second in relationship_rules:
    # The pair (customer, order) and the pair (order, customer) are the same relationship, so the names are sorted.
    pair = tuple(sorted((first, second)))
    # Store the maximum of this reading under the pair.
    pairs.setdefault(pair, []).append(maximum)
# Name the kind of every relationship from the two maxima.
for (a, b), maxima in pairs.items():
    # Two readings that both end in "many" make a many-to-many relationship.
    if maxima.count("many") == 2:
        # Lesson 2 shows why this kind must be split.
        kind = "many-to-many"
    # One reading that ends in "many" makes a one-to-many relationship.
    elif maxima.count("many") == 1:
        # This is the most frequent kind in a business database.
        kind = "one-to-many"
    # No reading that ends in "many": at most one on each side.
    else:
        # This kind is rare.
        kind = "one-to-one"
    # Print the pair with the kind of its relationship.
    print(f"{a.upper()} – {b.upper()}: {kind}")
