// Builds ios/data/foods/usda-subset.json from USDA FoodData Central SR Legacy (public domain).
// Usage: node ios/data/scripts/build-usda-subset.mjs <path-to-extracted-SR-Legacy-CSV-folder>
// Download: https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_csv_2018-04.zip
// Values per 100 g come straight from USDA. Arabic names are our translations, flagged
// `nameArSource: "machine_translated"` for review (ADR-011).
import { createReadStream, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { createInterface } from "node:readline";

const dir = process.argv[2];
if (!dir) throw new Error("pass the extracted SR Legacy CSV folder");

// [id, Arabic, English, regex on the USDA description, category]
const WANTED = [
  // Grains & bread
  ["rice-white-cooked", "أرز أبيض مطبوخ", "White rice, cooked", /^Rice, white, long-grain, regular, enriched, cooked$/, "grains"],
  ["rice-brown-cooked", "أرز بني مطبوخ", "Brown rice, cooked", /^Rice, brown, long-grain, cooked/, "grains"],
  ["pita-white", "خبز شامي أبيض", "Pita bread, white", /^Bread, pita, white, enriched$/, "bread"],
  ["pita-wholewheat", "خبز شامي بر", "Pita bread, whole wheat", /^Bread, pita, whole-wheat$/, "bread"],
  ["bread-white", "خبز توست أبيض", "White sandwich bread", /^Bread, white, commercially prepared \(includes soft bread crumbs\)$/, "bread"],
  ["bread-wholewheat", "خبز توست بر", "Whole-wheat sandwich bread", /^Bread, whole-wheat, commercially prepared$/, "bread"],
  ["pasta-cooked", "مكرونة مسلوقة", "Pasta, cooked", /^Pasta, cooked, enriched, without added salt$/, "grains"],
  ["noodles-egg-cooked", "نودلز بالبيض مسلوقة", "Egg noodles, cooked", /^Noodles, egg, cooked, enriched, with added salt$/, "grains"],
  ["bulgur-cooked", "برغل مطبوخ", "Bulgur, cooked", /^Bulgur, cooked$/, "grains"],
  ["couscous-cooked", "كسكسي مطبوخ", "Couscous, cooked", /^Couscous, cooked$/, "grains"],
  ["oats-dry", "شوفان", "Oats, dry", /^Cereals, oats, regular and quick, not fortified, dry$/, "grains"],
  ["semolina", "سميد", "Semolina", /^Semolina, enriched$/, "grains"],
  ["flour-white", "دقيق أبيض", "White flour", /^Wheat flour, white, all-purpose, enriched, bleached$/, "grains"],
  ["croissant", "كرواسون", "Croissant", /^Croissants, butter$/, "bread"],
  ["corn-flakes", "كورن فليكس", "Corn flakes", /^Cereals ready-to-eat, RALSTON Corn Flakes$/, "grains"],
  ["potato-boiled", "بطاطس مسلوقة", "Potatoes, boiled", /^Potatoes, boiled, cooked without skin, flesh, without salt$/, "vegetables"],
  ["potato-baked", "بطاطس مشوية", "Potatoes, baked", /^Potatoes, baked, flesh and skin, without salt$/, "vegetables"],
  ["french-fries", "بطاطس محمرة", "French fries", /^Fast foods, potato, french fried in vegetable oil$/, "fast_food"],
  ["sweet-potato-baked", "بطاطا مشوية", "Sweet potato, baked", /^Sweet potato, cooked, baked in skin, flesh, without salt$/, "vegetables"],
  // Eggs, dairy
  ["egg-raw", "بيض", "Egg, whole", /^Egg, whole, raw, fresh$/, "eggs"],
  ["egg-boiled", "بيض مسلوق", "Egg, hard-boiled", /^Egg, whole, cooked, hard-boiled$/, "eggs"],
  ["egg-fried", "بيض مقلي", "Egg, fried", /^Egg, whole, cooked, fried$/, "eggs"],
  ["egg-omelet", "أومليت", "Omelet", /^Egg, whole, cooked, omelet$/, "eggs"],
  ["milk-whole", "لبن كامل الدسم", "Milk, whole", /^Milk, whole, 3\.25% milkfat, with added vitamin D$/, "dairy"],
  ["milk-lowfat", "لبن قليل الدسم", "Milk, low-fat (1%)", /^Milk, lowfat, fluid, 1% milkfat, with added vitamin A and vitamin D$/, "dairy"],
  ["milk-skim", "لبن خالي الدسم", "Milk, skim", /^Milk, nonfat, fluid, with added vitamin A and vitamin D \(fat free or skim\)$/, "dairy"],
  ["yogurt-plain", "زبادي", "Yogurt, plain, whole milk", /^Yogurt, plain, whole milk$/, "dairy"],
  ["yogurt-greek", "زبادي يوناني خالي الدسم", "Greek yogurt, nonfat", /^Yogurt, Greek, plain, nonfat/, "dairy"],
  ["cheese-feta", "جبنة فيتا", "Feta cheese", /^Cheese, feta$/, "dairy"],
  ["cheese-mozzarella", "جبنة موتزاريلا", "Mozzarella", /^Cheese, mozzarella, whole milk$/, "dairy"],
  ["cheese-cheddar", "جبنة شيدر", "Cheddar", /^Cheese, cheddar \(Includes/, "dairy"],
  ["cheese-cream", "جبنة كريمي", "Cream cheese", /^Cheese, cream$/, "dairy"],
  ["cheese-cottage", "جبنة قريش (كوتاج)", "Cottage cheese, low-fat", /^Cheese, cottage, lowfat, 2% milkfat$/, "dairy"],
  ["cheese-processed", "جبنة مثلثات", "Processed cheese", /^Cheese, pasteurized process, American, fortified with vitamin D$/, "dairy"],
  ["butter", "زبدة", "Butter", /^Butter, salted$/, "fats"],
  ["ghee", "سمنة بلدي", "Ghee", /^Butter oil, anhydrous$/, "fats"],
  ["cream", "قشطة", "Heavy cream", /^Cream, fluid, heavy whipping$/, "dairy"],
  ["ice-cream-vanilla", "آيس كريم فانيليا", "Vanilla ice cream", /^Ice creams, vanilla$/, "sweets"],
  // Meat, poultry, fish
  ["chicken-breast-roasted", "صدر فراخ مشوي", "Chicken breast, roasted", /^Chicken, broilers or fryers, breast, meat only, cooked, roasted$/, "poultry"],
  ["chicken-thigh-roasted", "ورك فراخ مشوي", "Chicken thigh, roasted", /^Chicken, broilers or fryers, thigh, meat and skin, cooked, roasted$/, "poultry"],
  ["chicken-drumstick-roasted", "دبوس فراخ مشوي", "Chicken drumstick, roasted", /^Chicken, broilers or fryers, drumstick, meat and skin, cooked, roasted$/, "poultry"],
  ["chicken-wing-roasted", "جناح فراخ مشوي", "Chicken wing, roasted", /^Chicken, broilers or fryers, wing, meat and skin, cooked, roasted$/, "poultry"],
  ["chicken-breast-fried", "صدر فراخ مقلي", "Chicken breast, fried (batter)", /^Chicken, broilers or fryers, breast, meat and skin, cooked, fried, batter$/, "poultry"],
  ["turkey-roasted", "رومي مشوي", "Turkey, roasted", /^Turkey, whole, meat only, cooked, roasted$/, "poultry"],
  ["beef-ground-cooked", "لحم مفروم مطبوخ", "Ground beef (80/20), cooked", /^Beef, ground, 80% lean meat \/ 20% fat, patty, cooked, broiled$/, "meat"],
  ["beef-ground-lean-cooked", "لحم مفروم قليل الدهن", "Ground beef (90/10), cooked", /^Beef, ground, 90% lean meat \/ 10% fat, patty, cooked, broiled$/, "meat"],
  ["beef-steak", "ستيك لحم", "Beef steak (top sirloin), broiled", /^Beef, top sirloin, steak, separable lean and fat, trimmed to 1\/8" fat, choice, cooked, broiled$/, "meat"],
  ["lamb-cooked", "لحم ضاني مطبوخ", "Lamb, cooked", /^Lamb, composite of trimmed retail cuts, separable lean and fat, trimmed to 1\/4" fat, choice, cooked$/, "meat"],
  ["veal-cooked", "لحم بتلو", "Veal, cooked", /^Veal, composite of trimmed retail cuts, separable lean and fat, cooked$/, "meat"],
  ["beef-liver-fried", "كبدة بقري", "Beef liver, pan-fried", /^Beef, variety meats and by-products, liver, cooked, pan-fried$/, "meat"],
  ["chicken-liver", "كبدة فراخ", "Chicken liver, cooked", /^Chicken, liver, all classes, cooked, simmered$/, "poultry"],
  ["tilapia-cooked", "سمك بلطي مشوي", "Tilapia, cooked", /^Fish, tilapia, cooked, dry heat$/, "fish"],
  ["sardine-canned", "سردين معلب", "Sardines, canned in oil", /^Fish, sardine, Atlantic, canned in oil, drained solids with bone$/, "fish"],
  ["tuna-oil", "تونة بالزيت", "Tuna, canned in oil", /^Fish, tuna, light, canned in oil, drained solids$/, "fish"],
  ["tuna-water", "تونة بالماء", "Tuna, canned in water", /^Fish, tuna, light, canned in water, drained solids/, "fish"],
  ["salmon-cooked", "سلمون مشوي", "Salmon, cooked", /^Fish, salmon, Atlantic, farmed, cooked, dry heat$/, "fish"],
  ["mackerel-cooked", "ماكريل مشوي", "Mackerel, cooked", /^Fish, mackerel, Atlantic, cooked, dry heat$/, "fish"],
  ["shrimp-cooked", "جمبري مسلوق", "Shrimp, cooked", /^Crustaceans, shrimp, mixed species, cooked, moist heat/, "fish"],
  ["calamari-fried", "كاليماري مقلي", "Squid, fried", /^Mollusks, squid, mixed species, cooked, fried$/, "fish"],
  ["luncheon-beef", "لانشون بقري", "Beef bologna", /^Bologna, beef$/, "meat"],
  ["hot-dog", "سوسيس", "Beef frankfurter", /^Frankfurter, beef, unheated$/, "meat"],
  ["pastrami", "بسطرمة", "Pastrami", /^Beef, cured, pastrami$/, "meat"],
  ["turkey-breast-roasted", "صدر رومي مشوي", "Turkey breast, roasted", /^Turkey, breast, from whole bird, meat only, with added solution, roasted$/, "poultry"],
  // Legumes
  ["fava-cooked", "فول مسلوق", "Fava beans, cooked", /^Broadbeans \(fava beans\), mature seeds, cooked, boiled, without salt$/, "legumes"],
  ["lentils-cooked", "عدس مسلوق", "Lentils, cooked", /^Lentils, mature seeds, cooked, boiled, without salt$/, "legumes"],
  ["chickpeas-cooked", "حمص مسلوق", "Chickpeas, cooked", /^Chickpeas \(garbanzo beans, bengal gram\), mature seeds, cooked, boiled, without salt$/, "legumes"],
  ["kidney-beans-cooked", "فاصوليا حمراء مسلوقة", "Kidney beans, cooked", /^Beans, kidney, all types, mature seeds, cooked, boiled, without salt$/, "legumes"],
  ["white-beans-cooked", "فاصوليا بيضاء مسلوقة", "White beans, cooked", /^Beans, white, mature seeds, cooked, boiled, without salt$/, "legumes"],
  ["peas-cooked", "بسلة مسلوقة", "Green peas, cooked", /^Peas, green, frozen, cooked, boiled, drained, without salt$/, "vegetables"],
  // Vegetables
  ["tomato", "طماطم", "Tomato", /^Tomatoes, red, ripe, raw, year round average$/, "vegetables"],
  ["cucumber", "خيار", "Cucumber", /^Cucumber, with peel, raw$/, "vegetables"],
  ["lettuce", "خس", "Lettuce (romaine)", /^Lettuce, cos or romaine, raw$/, "vegetables"],
  ["onion", "بصل", "Onion", /^Onions, raw$/, "vegetables"],
  ["carrot", "جزر", "Carrot", /^Carrots, raw$/, "vegetables"],
  ["zucchini", "كوسة", "Zucchini", /^Squash, summer, zucchini, includes skin, raw$/, "vegetables"],
  ["eggplant", "باذنجان", "Eggplant", /^Eggplant, raw$/, "vegetables"],
  ["okra", "بامية", "Okra", /^Okra, raw$/, "vegetables"],
  ["spinach", "سبانخ", "Spinach", /^Spinach, raw$/, "vegetables"],
  ["jute-cooked", "ملوخية مسلوقة (ورق)", "Jute leaves (molokhia), cooked", /^Jute, potherb, cooked, boiled, drained, without salt$/, "vegetables"],
  ["pepper-green", "فلفل أخضر", "Green bell pepper", /^Peppers, sweet, green, raw$/, "vegetables"],
  ["pepper-red", "فلفل أحمر", "Red bell pepper", /^Peppers, sweet, red, raw$/, "vegetables"],
  ["cabbage", "كرنب", "Cabbage", /^Cabbage, raw$/, "vegetables"],
  ["cauliflower", "قرنبيط", "Cauliflower", /^Cauliflower, raw$/, "vegetables"],
  ["broccoli", "بروكلي", "Broccoli", /^Broccoli, raw$/, "vegetables"],
  ["green-beans", "فاصوليا خضراء", "Green beans", /^Beans, snap, green, raw$/, "vegetables"],
  ["corn", "ذرة", "Sweet corn", /^Corn, sweet, yellow, raw$/, "vegetables"],
  ["garlic", "ثوم", "Garlic", /^Garlic, raw$/, "vegetables"],
  ["parsley", "بقدونس", "Parsley", /^Parsley, fresh$/, "vegetables"],
  ["beets", "بنجر", "Beets", /^Beets, raw$/, "vegetables"],
  ["radish", "فجل", "Radish", /^Radishes, raw$/, "vegetables"],
  ["mushroom", "مشروم", "Mushrooms", /^Mushrooms, white, raw$/, "vegetables"],
  ["arugula", "جرجير", "Arugula", /^Arugula, raw$/, "vegetables"],
  ["olives-green", "زيتون أخضر", "Green olives", /^Olives, pickled, canned or bottled, green$/, "vegetables"],
  ["olives-black", "زيتون أسود", "Black olives", /^Olives, ripe, canned \(small-extra large\)$/, "vegetables"],
  // Fruits
  ["apple", "تفاح", "Apple", /^Apples, raw, with skin \(Includes foods for USDA's Food Distribution Program\)$/, "fruits"],
  ["banana", "موز", "Banana", /^Bananas, raw$/, "fruits"],
  ["orange", "برتقال", "Orange", /^Oranges, raw, all commercial varieties$/, "fruits"],
  ["tangerine", "يوسفي", "Mandarin", /^Tangerines, \(mandarin oranges\), raw$/, "fruits"],
  ["mango", "مانجو", "Mango", /^Mangos, raw$/, "fruits"],
  ["guava", "جوافة", "Guava", /^Guavas, common, raw$/, "fruits"],
  ["dates-medjool", "بلح مجدول", "Dates, Medjool", /^Dates, medjool$/, "fruits"],
  ["dates-deglet", "بلح (عجوة/نصف جاف)", "Dates, Deglet Noor", /^Dates, deglet noor$/, "fruits"],
  ["grapes", "عنب", "Grapes", /^Grapes, red or green \(European type, such as Thompson seedless\), raw$/, "fruits"],
  ["watermelon", "بطيخ", "Watermelon", /^Watermelon, raw$/, "fruits"],
  ["cantaloupe", "كانتلوب", "Cantaloupe", /^Melons, cantaloupe, raw$/, "fruits"],
  ["strawberry", "فراولة", "Strawberries", /^Strawberries, raw$/, "fruits"],
  ["figs", "تين", "Figs", /^Figs, raw$/, "fruits"],
  ["pomegranate", "رمان", "Pomegranate", /^Pomegranates, raw$/, "fruits"],
  ["apricot", "مشمش", "Apricot", /^Apricots, raw$/, "fruits"],
  ["peach", "خوخ", "Peach", /^Peaches, yellow, raw$/, "fruits"],
  ["pear", "كمثرى", "Pear", /^Pears, raw$/, "fruits"],
  ["plum", "برقوق", "Plum", /^Plums, raw$/, "fruits"],
  ["lemon", "ليمون", "Lemon", /^Lemons, raw, without peel$/, "fruits"],
  ["kiwi", "كيوي", "Kiwi", /^Kiwifruit, green, raw$/, "fruits"],
  ["pineapple", "أناناس", "Pineapple", /^Pineapple, raw, all varieties$/, "fruits"],
  ["raisins", "زبيب", "Raisins", /^Raisins, dark, seedless/, "fruits"],
  ["figs-dried", "تين مجفف", "Dried figs", /^Figs, dried, uncooked$/, "fruits"],
  ["apricots-dried", "مشمش مجفف", "Dried apricots", /^Apricots, dried, sulfured, uncooked$/, "fruits"],
  ["coconut-dried", "جوز هند مبشور", "Desiccated coconut", /^Nuts, coconut meat, dried \(desiccated\), not sweetened$/, "nuts"],
  // Nuts, seeds
  ["almonds", "لوز", "Almonds", /^Nuts, almonds$/, "nuts"],
  ["peanuts", "فول سوداني", "Peanuts, roasted", /^Peanuts, all types, dry-roasted, without salt$/, "nuts"],
  ["walnuts", "عين جمل", "Walnuts", /^Nuts, walnuts, english$/, "nuts"],
  ["pistachios", "فستق", "Pistachios", /^Nuts, pistachio nuts, dry roasted, without salt added$/, "nuts"],
  ["cashews", "كاجو", "Cashews", /^Nuts, cashew nuts, raw$/, "nuts"],
  ["hazelnuts", "بندق", "Hazelnuts", /^Nuts, hazelnuts or filberts$/, "nuts"],
  ["sesame", "سمسم", "Sesame seeds", /^Seeds, sesame seeds, whole, dried$/, "nuts"],
  ["tahini", "طحينة", "Tahini", /^Seeds, sesame butter, tahini, from roasted and toasted kernels \(most common type\)$/, "nuts"],
  ["peanut-butter", "زبدة فول سوداني", "Peanut butter", /^Peanut butter, smooth style, without salt$/, "nuts"],
  ["sunflower-seeds", "لب أبيض (عباد الشمس)", "Sunflower seeds", /^Seeds, sunflower seed kernels, dried$/, "nuts"],
  ["pumpkin-seeds", "لب سوري (قرع)", "Pumpkin seeds", /^Seeds, pumpkin and squash seed kernels, dried$/, "nuts"],
  // Oils, sweets, condiments
  ["olive-oil", "زيت زيتون", "Olive oil", /^Oil, olive, salad or cooking$/, "fats"],
  ["sunflower-oil", "زيت عباد الشمس", "Sunflower oil", /^Oil, sunflower, linoleic, \(approx\. 65%\)$/, "fats"],
  ["corn-oil", "زيت ذرة", "Corn oil", /^Oil, corn, industrial and retail, all purpose salad or cooking$/, "fats"],
  ["sugar", "سكر", "Sugar", /^Sugars, granulated$/, "sweets"],
  ["honey", "عسل نحل", "Honey", /^Honey$/, "sweets"],
  ["molasses", "عسل أسود", "Molasses", /^Molasses$/, "sweets"],
  ["jam", "مربى", "Jam", /^Jams and preserves$/, "sweets"],
  ["milk-chocolate", "شوكولاتة باللبن", "Milk chocolate", /^Candies, milk chocolate$/, "sweets"],
  ["dark-chocolate", "شوكولاتة داكنة", "Dark chocolate (70–85%)", /^Chocolate, dark, 70-85% cacao solids$/, "sweets"],
  ["biscuits-butter", "بسكويت بالزبدة", "Butter cookies", /^Cookies, butter, commercially prepared, enriched$/, "sweets"],
  ["cake-pound", "كيك", "Pound cake", /^Cake, pound, commercially prepared, butter \(includes fresh and frozen\)$/, "sweets"],
  ["donut", "دونات", "Doughnut", /^Doughnuts, cake-type, plain \(includes unsugared, old-fashioned\)$/, "sweets"],
  ["ketchup", "كاتشب", "Ketchup", /^Catsup$/, "condiments"],
  ["mayonnaise", "مايونيز", "Mayonnaise", /^Salad dressing, mayonnaise, regular$/, "condiments"],
  ["mustard", "مسطردة", "Mustard", /^Mustard, prepared, yellow$/, "condiments"],
  ["tomato-paste", "صلصة طماطم (معجون)", "Tomato paste", /^Tomato products, canned, paste, without salt added/, "condiments"],
  // Snacks, fast food, drinks
  ["chips", "شيبسي", "Potato chips", /^Snacks, potato chips, plain, salted$/, "snacks"],
  ["popcorn", "فشار", "Popcorn, air-popped", /^Snacks, popcorn, air-popped$/, "snacks"],
  ["burger", "برجر (ساندوتش)", "Hamburger sandwich", /^Fast foods, hamburger; single, regular patty; plain$/, "fast_food"],
  ["pizza-cheese", "بيتزا جبنة", "Cheese pizza", /^Fast Food, Pizza Chain, 14" pizza, cheese topping, regular crust$/, "fast_food"],
  ["chicken-nuggets", "ناجتس", "Chicken nuggets", /^Fast foods, chicken tenders$/, "fast_food"],
  ["tea-brewed", "شاي (بدون سكر)", "Tea, brewed, unsweetened", /^Beverages, tea, black, brewed, prepared with tap water$/, "drinks"],
  ["coffee-brewed", "قهوة (بدون سكر)", "Coffee, brewed, unsweetened", /^Beverages, coffee, brewed, prepared with tap water$/, "drinks"],
  ["cola", "مياه غازية (كولا)", "Cola", /^Beverages, carbonated, cola, regular$/, "drinks"],
  ["orange-juice", "عصير برتقال فريش", "Orange juice, fresh", /^Orange juice, raw/, "drinks"],
  ["apple-juice", "عصير تفاح", "Apple juice", /^Apple juice, canned or bottled, unsweetened, without added ascorbic acid$/, "drinks"],
];

const NUTRIENTS = { 1008: "kcal", 1003: "protein", 1004: "fat", 1005: "carbs" };

function parseCSVLine(line) {
  const out = [];
  let cur = "", quoted = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (quoted) {
      if (ch === '"' && line[i + 1] === '"') { cur += '"'; i++; }
      else if (ch === '"') quoted = false;
      else cur += ch;
    } else if (ch === '"') quoted = true;
    else if (ch === ",") { out.push(cur); cur = ""; }
    else cur += ch;
  }
  out.push(cur);
  return out;
}

const foods = readFileSync(join(dir, "food.csv"), "utf8").split("\n").slice(1).filter(Boolean).map(parseCSVLine);
const picks = new Map();
const missing = [];
for (const [id, ar, en, re, category] of WANTED) {
  const row = foods.find((f) => re.test(f[2]));
  if (!row) { missing.push(`${id}: ${re}`); continue; }
  picks.set(row[0], { id: `usda-${id}`, nameAr: ar, nameEn: en, category, fdcId: Number(row[0]), usdaDescription: row[2] });
}

const values = new Map();
const rl = createInterface({ input: createReadStream(join(dir, "food_nutrient.csv")) });
for await (const line of rl) {
  const [, fdc, nutrient, amount] = parseCSVLine(line);
  if (!picks.has(fdc) || !NUTRIENTS[nutrient]) continue;
  const v = values.get(fdc) ?? {};
  v[NUTRIENTS[nutrient]] = Number(amount);
  values.set(fdc, v);
}

const out = [];
for (const [fdc, food] of picks) {
  const v = values.get(fdc) ?? {};
  if (["kcal", "protein", "carbs", "fat"].some((k) => typeof v[k] !== "number")) { missing.push(`${food.id}: incomplete nutrients`); continue; }
  out.push({
    ...food,
    nameArSource: "machine_translated",
    per100: { kcal: v.kcal, protein: v.protein, carbs: v.carbs, fat: v.fat },
    source: "usda",
  });
}

if (missing.length) {
  console.error("UNMATCHED:\n" + missing.join("\n"));
}
writeFileSync(new URL("../foods/usda-subset.json", import.meta.url), JSON.stringify(out, null, 1) + "\n");
console.log(`wrote ${out.length} USDA foods (${missing.length} unmatched)`);
