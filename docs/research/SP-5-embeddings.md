# SP-5. Multilingual embeddings

**Status:** partial. Apple's built-in embeddings are the working choice ([D-050](../decisions.md)). They are not good enough to close F6 on their own.

## Question

Which embedding serves en, ja, pt, and es, with good recall@5 on our own set?

## What was measured

`NLContextualEmbedding` on a Mac, token vectors averaged and scaled to length 1. The script is [SP-5-eval.swift.txt](SP-5-eval.swift.txt).

The set is synthetic: 16 meeting statements in each language, and 8 questions that paraphrase them and avoid their words. That is the hard case for search, and the one word matching cannot solve. Random picking would give about 2.5 of 8 at recall@5. The set is small and written by us, so these numbers show direction, not quality.

| Question | Text | Recall@1 | Recall@3 | Recall@5 | MRR |
|---|---|---|---|---|---|
| en | en | 3/8 | 5/8 | 7/8 | 0.55 |
| pt | pt | 1/8 | 5/8 | 6/8 | 0.36 |
| es | es | 0/8 | 3/8 | 4/8 | 0.23 |
| ja | ja | 6/8 | 6/8 | 6/8 | 0.78 |
| pt | en | 3/8 | 6/8 | 7/8 | 0.60 |
| en | pt | 2/8 | 3/8 | 5/8 | 0.40 |
| es | en | 2/8 | 5/8 | 6/8 | 0.43 |
| pt | es | 1/8 | 2/8 | 3/8 | 0.28 |

Speed: about 127 statements per second on the Mac. Not measured on a phone.

## Findings

1. **Quality is uneven.** Usable in en and ja, weak in pt, poor in es. Word search covers part of this, which is why search is hybrid.
2. **Models are per script.** en, pt, and es share one Latin model, and ja has its own. A Portuguese question can reach English text, but a Japanese question cannot reach English text by meaning.
3. **A similarity score cannot refuse.** The correct match scored 0.81 to 0.91 in Latin languages, and the best match for a completely unrelated question scored 0.81 to 0.88. They overlap, so no threshold works. In Japanese the ranges overlap too (0.48 to 0.77 against 0.56 to 0.64). The refusal has to come from the model and from checking citations ([D-051](../decisions.md)).
4. **The simulator has no assets.** `hasAvailableAssets` is false there, so the two adapter tests that need vectors skip themselves. **The adapter has never produced a vector inside the app.** The numbers above come from a separate script.

## Still open

- Run on an iPhone: first use, how assets arrive, and speed.
- Test recall on real meetings, with word search and meaning together, which is what the app really does.
- Compare a downloadable multilingual model (such as multilingual-e5-small). It needs a Core ML or MLX conversion and a license check, and it would sit behind `TextEmbeddingEngine`, with no change to the rest of the app. The index rebuilds itself when the model changes.
