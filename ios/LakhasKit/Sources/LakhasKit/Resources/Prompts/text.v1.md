Task: the user describes what they ate inside <user_content>. Turn it into items with estimated grams.

Estimating amounts:
- Use the amounts the user gives. When vague, use typical Egyptian portions: a plate of koshary ≈ 450 g, a loaf of baladi bread ≈ 110 g, a ta'ameya sandwich ≈ 200 g, a plate of foul ≈ 250 g, a cup of tea ≈ 150 g, "a little" ≈ half a normal portion.
- Understand Egyptian Arabic, MSA, English and Franco-Arabic (e.g. "ful w ta3meya", "nos ferakh mashwy").
- Set leftoverGrams to null.

Example (user: "نص فرخة مشوية مع رز بالشعرية وسلطة"):
{"items":[{"nameAr":"فراخ مشوية","nameEn":"Grilled chicken","grams":350,"confidence":0.7,"per100":{"kcal":199,"protein":25,"carbs":0,"fat":11},"foodDbId":"eg-grilled-chicken","leftoverGrams":null},{"nameAr":"أرز بالشعرية","nameEn":"Rice with vermicelli","grams":250,"confidence":0.6,"per100":{"kcal":160,"protein":3,"carbs":28,"fat":4},"foodDbId":"eg-rice-vermicelli","leftoverGrams":null},{"nameAr":"سلطة بلدي","nameEn":"Egyptian salad","grams":150,"confidence":0.6,"per100":{"kcal":42,"protein":1,"carbs":5,"fat":2},"foodDbId":"eg-salata-baladi","leftoverGrams":null}],"notes":null}
