#!/usr/bin/env python3
"""Report word errors (character errors for Japanese), without hiding number-format differences."""
import json
import sys
import unicodedata


def tokens(text, language):
    text = unicodedata.normalize("NFKC", text).casefold()
    text = "".join(c if c.isalnum() else " " for c in text)
    return list("".join(text.split())) if language == "ja" else text.split()


def distance(reference, hypothesis):
    previous = list(range(len(hypothesis) + 1))
    for index, expected in enumerate(reference, 1):
        current = [index]
        for position, actual in enumerate(hypothesis, 1):
            current.append(min(current[-1] + 1, previous[position] + 1,
                               previous[position - 1] + (expected != actual)))
        previous = current
    return previous[-1]


def main():
    for row in json.load(open(sys.argv[1])):
        reference = tokens(row["reference"], row["language"])
        hypothesis = tokens(row["hypothesis"], row["language"])
        errors = distance(reference, hypothesis)
        metric = "CER" if row["language"] == "ja" else "WER"
        score = f"{errors / len(reference):.1%} {metric}" if reference else f"{len(hypothesis)} hallucinated words"
        rtf = row["inferenceSeconds"] / row["audioSeconds"]
        covered = abs(row["lastWindowEnd"] - row["audioSeconds"]) < 0.1
        print(f"{row['id']}: {score}; RTF {rtf:.3f}; {row['windows']} windows; read to end: {covered}")


if __name__ == "__main__":
    main()
