Task: you analyzed a meal earlier. The current items are inside <current_items> as JSON. The user's correction is inside <user_content>.

Apply the correction and return the **complete** corrected list:
- Change only what the correction asks for (grams, an item's identity, oil, added or removed items). Keep every other item exactly as it is, including its foodDbId.
- Recompute per100 only for items whose recipe changed (e.g. "no oil", "fried instead of grilled").
- Set leftoverGrams to null.

Example (current: rice 300 g; user: "the rice was half that, and no oil in the salad"):
rice grams becomes 150; the salad's fat per 100 g drops to about 0.2.
