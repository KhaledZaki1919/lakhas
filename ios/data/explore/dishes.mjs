// Curated Explore dishes (PROJECT_PROMPT.md §4.5, ADR-026). Hand-written for Lakhas; every
// ingredient points at a food in the bundled DB (foods.json), so calories and macros come from
// the DB's per-100 g values. Amounts are for `servings` (1 unless noted), with a household
// measure in both languages. All values are estimates.
//
// ing(foodId, grams, measureAr, measureEn)
// Categories pick the placeholder plate: beans, eggs, dairy, bread, rice, stew, grill, fish,
// salad, soup, pasta, sweet, fruit, snack, drink.

const ing = (food, grams, ar, en) => ({ food, grams, measureAr: ar, measureEn: en });

const B = 'breakfast', L = 'lunch', D = 'dinner', S = 'snack';
const lose = 'lose', maintain = 'maintain', gain = 'gain';

export const dishes = [
  // ── Egyptian breakfast ────────────────────────────────────────────────────────────────
  {
    id: 'foul-plate', nameAr: 'طبق فول بالزيت وعيش بلدي', nameEn: 'Foul with oil and baladi bread',
    aliasesAr: ['فول مدمس', 'فطار مصري', 'فول بالزيت الحار'], aliasesEn: ['ful medames', 'fava beans breakfast'],
    category: 'beans', meals: [B, D], goals: [maintain, gain],
    ingredients: [
      ing('eg-foul-medames-oil', 250, 'طبق', 'plate'),
      ing('eg-baladi-bread', 110, 'رغيف', 'loaf'),
      ing('eg-salata-baladi', 100, 'طبق صغير', 'small bowl'),
      ing('eg-torshi', 30, 'قطعة مخلل', 'piece of pickle'),
    ],
  },
  {
    id: 'foul-light', nameAr: 'فول خفيف بالليمون وسلطة', nameEn: 'Light foul with lemon and salad',
    aliasesAr: ['فول سادة', 'فول دايت'], aliasesEn: ['plain foul', 'diet foul'],
    category: 'beans', meals: [B, D], goals: [lose, maintain],
    ingredients: [
      ing('eg-foul-plain', 200, 'طبق صغير', 'small plate'),
      ing('eg-baladi-bread', 55, 'نص رغيف', 'half loaf'),
      ing('eg-salata-baladi', 150, 'طبق', 'bowl'),
      ing('usda-lemon', 15, 'نص ليمونة', 'half a lemon'),
    ],
  },
  {
    id: 'foul-tahini-plate', nameAr: 'فول بالطحينة', nameEn: 'Foul with tahini',
    aliasesAr: ['فول طحينة'], aliasesEn: ['ful with tahini'],
    category: 'beans', meals: [B, D], goals: [maintain],
    ingredients: [
      ing('eg-foul-tahini', 250, 'طبق', 'plate'),
      ing('eg-baladi-bread', 110, 'رغيف', 'loaf'),
    ],
  },
  {
    id: 'foul-eskandarani-plate', nameAr: 'فول إسكندراني', nameEn: 'Alexandrian foul',
    aliasesAr: ['فول اسكندراني بالخضار'], aliasesEn: ['foul eskandarani', 'alexandria foul'],
    category: 'beans', meals: [B, D], goals: [lose, maintain],
    ingredients: [
      ing('eg-foul-eskandarani', 250, 'طبق', 'plate'),
      ing('eg-baladi-bread', 55, 'نص رغيف', 'half loaf'),
    ],
  },
  {
    id: 'taameya-plate', nameAr: 'طبق طعمية بالطحينة', nameEn: "Ta'ameya plate with tahini",
    aliasesAr: ['فلافل', 'طعميه', 'طعمية وسلطة'], aliasesEn: ['falafel plate', 'taameya', 'tamiya'],
    category: 'beans', meals: [B, D], goals: [maintain, gain],
    ingredients: [
      ing('eg-taameya', 150, '5 أقراص', '5 pieces'),
      ing('eg-baladi-bread', 110, 'رغيف', 'loaf'),
      ing('eg-tahini-salad', 30, 'ملعقتين', '2 tablespoons'),
      ing('eg-salata-baladi', 100, 'طبق صغير', 'small bowl'),
    ],
  },
  {
    id: 'taameya-sandwich', nameAr: 'ساندوتش طعمية', nameEn: "Ta'ameya sandwich",
    aliasesAr: ['سندوتش فلافل', 'ساندويتش طعميه'], aliasesEn: ['falafel sandwich', 'taameya sandwich'],
    category: 'bread', meals: [B, S], goals: [maintain],
    ingredients: [ing('eg-taameya-sandwich', 200, 'ساندوتش', 'sandwich')],
  },
  {
    id: 'foul-sandwich', nameAr: 'ساندوتش فول', nameEn: 'Foul sandwich',
    aliasesAr: ['سندوتش فول', 'ساندويتش فول'], aliasesEn: ['ful sandwich'],
    category: 'bread', meals: [B, S], goals: [lose, maintain],
    ingredients: [ing('eg-foul-sandwich', 180, 'ساندوتش', 'sandwich')],
  },
  {
    id: 'eggs-pastirma-plate', nameAr: 'بيض بالبسطرمة', nameEn: 'Eggs with pastirma',
    aliasesAr: ['بيض بسطرمة', 'بسطرمه'], aliasesEn: ['pastrami eggs', 'basterma eggs'],
    category: 'eggs', meals: [B], goals: [maintain, gain],
    ingredients: [
      ing('eg-eggs-pastirma', 150, 'طاسة صغيرة', 'small pan'),
      ing('eg-baladi-bread', 55, 'نص رغيف', 'half loaf'),
    ],
  },
  {
    id: 'shakshuka-plate', nameAr: 'شكشوكة', nameEn: 'Shakshuka',
    aliasesAr: ['شكشوكه', 'بيض بالطماطم'], aliasesEn: ['shakshouka', 'eggs in tomato'],
    category: 'eggs', meals: [B, D], goals: [lose, maintain],
    ingredients: [
      ing('eg-shakshuka', 250, 'طاسة', 'pan'),
      ing('eg-baladi-bread', 55, 'نص رغيف', 'half loaf'),
    ],
  },
  {
    id: 'areesh-salad-plate', nameAr: 'جبنة قريش بالطماطم والخيار', nameEn: 'Areesh cheese with tomato and cucumber',
    aliasesAr: ['جبنه قريش', 'قريش بالطماطم'], aliasesEn: ['cottage cheese egyptian', 'areesh'],
    category: 'dairy', meals: [B, D], goals: [lose, maintain],
    ingredients: [
      ing('eg-gibna-areesh', 100, 'قطعة', 'piece'),
      ing('usda-tomato', 120, 'طماطماية', 'tomato'),
      ing('usda-cucumber', 100, 'خيارة', 'cucumber'),
      ing('usda-olive-oil', 5, 'ملعقة صغيرة', 'teaspoon'),
      ing('eg-baladi-bread', 55, 'نص رغيف', 'half loaf'),
    ],
  },
  {
    id: 'domiati-breakfast', nameAr: 'فطار جبنة بيضا وطماطم', nameEn: 'White cheese and tomato breakfast',
    aliasesAr: ['جبنة دمياطي', 'جبنه بيضاء'], aliasesEn: ['domiati cheese', 'white cheese breakfast'],
    category: 'dairy', meals: [B, D], goals: [maintain],
    ingredients: [
      ing('eg-gibna-domiati', 60, 'شريحتين', '2 slices'),
      ing('usda-tomato', 120, 'طماطماية', 'tomato'),
      ing('eg-baladi-bread', 110, 'رغيف', 'loaf'),
      ing('usda-olives-black', 20, '5 زيتونات', '5 olives'),
    ],
  },
  {
    id: 'boiled-eggs-plate', nameAr: 'بيض مسلوق وعيش أسمر', nameEn: 'Boiled eggs with whole-wheat pita',
    aliasesAr: ['بيض مسلوق', 'بيضتين مسلوق'], aliasesEn: ['hard boiled eggs', 'eggs breakfast'],
    category: 'eggs', meals: [B, D], goals: [lose, maintain],
    ingredients: [
      ing('usda-egg-boiled', 100, 'بيضتين', '2 eggs'),
      ing('usda-pita-wholewheat', 64, 'رغيف', 'loaf'),
      ing('usda-cucumber', 100, 'خيارة', 'cucumber'),
      ing('usda-tomato', 60, 'نص طماطماية', 'half a tomato'),
    ],
  },
  {
    id: 'cheese-omelet', nameAr: 'أومليت بالجبنة الفيتا', nameEn: 'Feta omelet with toast',
    aliasesAr: ['اومليت', 'عجة بالجبنة'], aliasesEn: ['omelette', 'cheese omelet'],
    category: 'eggs', meals: [B, D], goals: [maintain],
    ingredients: [
      ing('usda-egg-omelet', 120, 'بيضتين', '2 eggs'),
      ing('usda-cheese-feta', 30, 'قطعة صغيرة', 'small piece'),
      ing('usda-bread-wholewheat', 64, 'شريحتين توست', '2 slices of toast'),
    ],
  },
  {
    id: 'eggs-ghee-plate', nameAr: 'بيض بالسمنة البلدي', nameEn: 'Eggs fried in ghee',
    aliasesAr: ['بيض مقلي بالسمنه', 'بيض عيون'], aliasesEn: ['fried eggs ghee'],
    category: 'eggs', meals: [B], goals: [gain],
    ingredients: [
      ing('eg-eggs-ghee', 110, 'بيضتين', '2 eggs'),
      ing('eg-baladi-bread', 110, 'رغيف', 'loaf'),
      ing('eg-gibna-domiati', 30, 'شريحة', 'slice'),
    ],
  },
  {
    id: 'bessara-plate', nameAr: 'بصارة بالبصل المحمر', nameEn: 'Bessara with fried onion',
    aliasesAr: ['بيصارة', 'بصاره'], aliasesEn: ['bissara', 'besara'],
    category: 'beans', meals: [B, L, D], goals: [lose, maintain],
    ingredients: [
      ing('eg-bessara', 250, 'طبق', 'plate'),
      ing('eg-baladi-bread', 55, 'نص رغيف', 'half loaf'),
      ing('usda-onion', 30, 'ربع بصلة', 'quarter onion'),
    ],
  },
  {
    id: 'feteer-honey', nameAr: 'فطير مشلتت بالعسل والجبنة القريش', nameEn: 'Feteer with honey and areesh cheese',
    aliasesAr: ['فطير بالعسل', 'فطير فلاحي'], aliasesEn: ['feteer meshaltet', 'fiteer with honey'],
    category: 'bread', meals: [B], goals: [gain],
    ingredients: [
      ing('eg-feteer-meshaltet', 125, 'ربع فطيرة', 'quarter pie'),
      ing('usda-honey', 21, 'ملعقة كبيرة', 'tablespoon'),
      ing('eg-gibna-areesh', 50, 'نص قطعة', 'half piece'),
    ],
  },
  {
    id: 'halawa-sandwich', nameAr: 'ساندوتش حلاوة طحينية', nameEn: 'Halawa sandwich',
    aliasesAr: ['حلاوه', 'عيش وحلاوة'], aliasesEn: ['halva sandwich', 'tahini halva'],
    category: 'bread', meals: [B, S], goals: [gain],
    ingredients: [
      ing('eg-halawa', 40, 'ملعقتين', '2 tablespoons'),
      ing('eg-baladi-bread', 110, 'رغيف', 'loaf'),
    ],
  },
  {
    id: 'fino-cheese', nameAr: 'عيش فينو بالجبنة والخيار', nameEn: 'Fino roll with cheese and cucumber',
    aliasesAr: ['فينو بالجبنه', 'ساندوتش جبنة'], aliasesEn: ['cheese roll', 'fino sandwich'],
    category: 'bread', meals: [B, S], goals: [maintain],
    ingredients: [
      ing('eg-fino-bread', 70, 'رغيف فينو', 'roll'),
      ing('usda-cheese-processed', 34, 'مثلثين جبنة', '2 cheese wedges'),
      ing('usda-cucumber', 50, 'نص خيارة', 'half a cucumber'),
    ],
  },
  {
    id: 'hummus-breakfast', nameAr: 'حمص بالطحينة وعيش شامي', nameEn: 'Hummus with pita',
    aliasesAr: ['حمص', 'حمص بطحينة'], aliasesEn: ['hommos', 'houmous'],
    category: 'beans', meals: [B, D, S], goals: [maintain],
    ingredients: [
      ing('eg-hummus', 150, 'طبق صغير', 'small bowl'),
      ing('usda-olive-oil', 7, 'نص ملعقة', 'half tablespoon'),
      ing('usda-pita-white', 60, 'رغيف', 'loaf'),
      ing('usda-cucumber', 100, 'خيارة', 'cucumber'),
    ],
  },
  {
    id: 'ful-nabet-bowl', nameAr: 'شوربة فول نابت', nameEn: 'Ful nabet soup',
    aliasesAr: ['فول نابت', 'شوربه فول نابت'], aliasesEn: ['sprouted fava soup'],
    category: 'soup', meals: [B, D], goals: [lose, maintain],
    ingredients: [
      ing('eg-ful-nabet', 300, 'سلطانية', 'bowl'),
      ing('eg-baladi-bread', 28, 'ربع رغيف', 'quarter loaf'),
      ing('usda-lemon', 15, 'نص ليمونة', 'half a lemon'),
    ],
  },

  // ── Everyday healthy breakfast ─────────────────────────────────────────────────────────
  {
    id: 'oats-banana', nameAr: 'شوفان باللبن والموز', nameEn: 'Oats with milk and banana',
    aliasesAr: ['شوفان', 'بليلة شوفان'], aliasesEn: ['oatmeal', 'porridge'],
    category: 'dairy', meals: [B], goals: [lose, maintain],
    ingredients: [
      ing('usda-oats-dry', 40, 'نص كوب', 'half cup'),
      ing('usda-milk-lowfat', 244, 'كوب', 'cup'),
      ing('usda-banana', 118, 'موزة', 'banana'),
      ing('usda-honey', 7, 'ملعقة صغيرة', 'teaspoon'),
    ],
  },
  {
    id: 'greek-yogurt-bowl', nameAr: 'زبادي يوناني بالفراولة واللوز', nameEn: 'Greek yogurt with strawberries and almonds',
    aliasesAr: ['زبادي يوناني', 'جريك يوجرت'], aliasesEn: ['yogurt bowl', 'greek yoghurt'],
    category: 'dairy', meals: [B, S], goals: [lose, maintain],
    ingredients: [
      ing('usda-yogurt-greek', 170, 'علبة', 'tub'),
      ing('usda-strawberry', 100, '7 حبات', '7 berries'),
      ing('usda-almonds', 15, '10 حبات', '10 almonds'),
      ing('usda-honey', 10, 'ملعقة صغيرة', 'teaspoon'),
    ],
  },
  {
    id: 'cottage-fruit', nameAr: 'جبنة قريش بالأناناس', nameEn: 'Cottage cheese with pineapple',
    aliasesAr: ['كوتيج', 'جبنة كوتيدج'], aliasesEn: ['cottage cheese bowl'],
    category: 'dairy', meals: [B, S], goals: [lose],
    ingredients: [
      ing('usda-cheese-cottage', 150, 'نص علبة', 'half tub'),
      ing('usda-pineapple', 100, 'كوب مكعبات', 'cup of chunks'),
    ],
  },
  {
    id: 'pb-toast-banana', nameAr: 'توست أسمر بزبدة الفول السوداني والموز', nameEn: 'Peanut butter toast with banana',
    aliasesAr: ['زبدة فول سوداني', 'بينات بتر'], aliasesEn: ['pb toast', 'peanut butter banana'],
    category: 'bread', meals: [B, S], goals: [gain, maintain],
    ingredients: [
      ing('usda-bread-wholewheat', 64, 'شريحتين توست', '2 slices of toast'),
      ing('usda-peanut-butter', 32, 'ملعقتين', '2 tablespoons'),
      ing('usda-banana', 118, 'موزة', 'banana'),
    ],
  },
  {
    id: 'banana-smoothie', nameAr: 'سموذي موز باللبن والشوفان', nameEn: 'Banana, milk and oat smoothie',
    aliasesAr: ['عصير موز باللبن', 'سموثي'], aliasesEn: ['banana shake', 'smoothie'],
    category: 'drink', meals: [B, S], goals: [gain],
    ingredients: [
      ing('usda-banana', 118, 'موزة', 'banana'),
      ing('usda-milk-whole', 244, 'كوب', 'cup'),
      ing('usda-oats-dry', 20, '3 ملاعق', '3 tablespoons'),
      ing('usda-honey', 10, 'ملعقة صغيرة', 'teaspoon'),
    ],
  },

  // ── Egyptian lunch and dinner ──────────────────────────────────────────────────────────
  {
    id: 'koshary-medium', nameAr: 'كشري طبق وسط', nameEn: 'Koshary, medium plate',
    aliasesAr: ['كشرى', 'كشري مصري'], aliasesEn: ['koshari', 'kushari', 'koshary'],
    category: 'rice', meals: [L, D], goals: [maintain, gain],
    ingredients: [ing('eg-koshary', 450, 'طبق وسط', 'medium plate')],
  },
  {
    id: 'koshary-small-salad', nameAr: 'كشري صغير مع سلطة', nameEn: 'Small koshary with salad',
    aliasesAr: ['كشرى صغير', 'كشري دايت'], aliasesEn: ['small koshari', 'koshary light'],
    category: 'rice', meals: [L, D], goals: [lose, maintain],
    ingredients: [
      ing('eg-koshary', 300, 'طبق صغير', 'small plate'),
      ing('eg-salata-baladi', 150, 'طبق', 'bowl'),
    ],
  },
  {
    id: 'molokhia-chicken-rice', nameAr: 'ملوخية بالفراخ والرز', nameEn: 'Molokhia with chicken and rice',
    aliasesAr: ['ملوخيه', 'ملوخية وفراخ', 'ملوخيا'], aliasesEn: ['mulukhiyah', 'molokheya', 'jute leaf stew'],
    category: 'stew', meals: [L, D], goals: [maintain, gain],
    ingredients: [
      ing('eg-molokhia', 300, 'سلطانية', 'bowl'),
      ing('eg-grilled-chicken', 175, 'ربع فرخة', 'quarter chicken'),
      ing('eg-rice-egyptian-white', 160, 'كوب', 'cup'),
    ],
  },
  {
    id: 'molokhia-light', nameAr: 'ملوخية بصدر الفراخ (خفيفة)', nameEn: 'Light molokhia with chicken breast',
    aliasesAr: ['ملوخيه دايت', 'ملوخية صدور'], aliasesEn: ['molokhia diet', 'mulukhiyah light'],
    category: 'stew', meals: [L, D], goals: [lose, maintain],
    ingredients: [
      ing('eg-molokhia', 300, 'سلطانية', 'bowl'),
      ing('usda-chicken-breast-roasted', 150, 'صدر صغير', 'small breast'),
      ing('eg-rice-egyptian-white', 100, 'ثلثي كوب', '2/3 cup'),
    ],
  },
  {
    id: 'mahshi-plate', nameAr: 'طبق محشي مشكل', nameEn: 'Mixed mahshi plate',
    aliasesAr: ['محشى', 'محشي كرنب وكوسة', 'محاشي'], aliasesEn: ['mahshi', 'stuffed vegetables'],
    category: 'rice', meals: [L, D], goals: [maintain],
    ingredients: [
      ing('eg-mahshi-mix', 350, 'طبق', 'plate'),
      ing('usda-yogurt-plain', 100, 'نص علبة زبادي', 'half tub of yogurt'),
    ],
  },
  {
    id: 'waraq-enab-yogurt', nameAr: 'ورق عنب بالزبادي', nameEn: 'Stuffed grape leaves with yogurt',
    aliasesAr: ['ورق عنب', 'محشي ورق عنب', 'دولمة'], aliasesEn: ['dolma', 'warak enab', 'vine leaves'],
    category: 'rice', meals: [L, D, S], goals: [maintain],
    ingredients: [
      ing('eg-mahshi-waraq-enab', 150, '10 صوابع', '10 pieces'),
      ing('usda-yogurt-plain', 100, 'نص علبة', 'half tub'),
    ],
  },
  {
    id: 'mahshi-kromb-plate', nameAr: 'محشي كرنب', nameEn: 'Stuffed cabbage rolls',
    aliasesAr: ['كرنب محشي', 'محشى كرمب'], aliasesEn: ['cabbage mahshi', 'stuffed cabbage'],
    category: 'rice', meals: [L, D], goals: [maintain],
    ingredients: [
      ing('eg-mahshi-kromb', 300, '10 صوابع', '10 rolls'),
      ing('eg-salata-baladi', 100, 'طبق صغير', 'small bowl'),
    ],
  },
  {
    id: 'fattah-meat-plate', nameAr: 'فتة باللحمة', nameEn: 'Fattah with meat',
    aliasesAr: ['فته', 'فتة لحمة', 'فتة العيد'], aliasesEn: ['fatta', 'fatteh meat'],
    category: 'rice', meals: [L, D], goals: [gain],
    ingredients: [ing('eg-fattah-meat', 400, 'طبق', 'plate')],
  },
  {
    id: 'fattah-chicken-plate', nameAr: 'فتة بالفراخ', nameEn: 'Fattah with chicken',
    aliasesAr: ['فته فراخ'], aliasesEn: ['fatta chicken', 'fatteh chicken'],
    category: 'rice', meals: [L, D], goals: [maintain, gain],
    ingredients: [ing('eg-fattah-chicken', 400, 'طبق', 'plate')],
  },
  {
    id: 'bamia-rice', nameAr: 'بامية باللحمة ورز بالشعرية', nameEn: 'Okra stew with meat and vermicelli rice',
    aliasesAr: ['باميه', 'بامية'], aliasesEn: ['bamya', 'okra stew'],
    category: 'stew', meals: [L, D], goals: [maintain],
    ingredients: [
      ing('eg-bamia', 300, 'سلطانية', 'bowl'),
      ing('eg-rice-vermicelli', 160, 'كوب', 'cup'),
    ],
  },
  {
    id: 'fasolia-rice', nameAr: 'فاصوليا خضرا ورز', nameEn: 'Green bean stew with rice',
    aliasesAr: ['فاصوليا خضراء', 'فاصوليه'], aliasesEn: ['fasolia', 'green beans stew'],
    category: 'stew', meals: [L, D], goals: [lose, maintain],
    ingredients: [
      ing('eg-fasolia-khadra', 300, 'سلطانية', 'bowl'),
      ing('eg-rice-egyptian-white', 120, '3 أرباع كوب', '3/4 cup'),
    ],
  },
  {
    id: 'bisella-rice', nameAr: 'بسلة بالجزر ورز', nameEn: 'Peas and carrots with rice',
    aliasesAr: ['بسله', 'بازلاء بالجزر'], aliasesEn: ['bisella', 'peas stew'],
    category: 'stew', meals: [L, D], goals: [maintain],
    ingredients: [
      ing('eg-bisella', 300, 'سلطانية', 'bowl'),
      ing('eg-rice-vermicelli', 160, 'كوب', 'cup'),
    ],
  },
  {
    id: 'spinach-rice', nameAr: 'سبانخ ورز', nameEn: 'Spinach stew with rice',
    aliasesAr: ['سبانخ باللحمة', 'سبانخ'], aliasesEn: ['spinach stew'],
    category: 'stew', meals: [L, D], goals: [lose, maintain],
    ingredients: [
      ing('eg-spinach-stew', 300, 'سلطانية', 'bowl'),
      ing('eg-rice-egyptian-white', 120, '3 أرباع كوب', '3/4 cup'),
    ],
  },
  {
    id: 'torly-rice', nameAr: 'تورلي خضار ورز', nameEn: 'Mixed vegetable stew with rice',
    aliasesAr: ['طورلي', 'خضار مشكل بالصلصة'], aliasesEn: ['torly', 'turli', 'vegetable stew'],
    category: 'stew', meals: [L, D], goals: [lose, maintain],
    ingredients: [
      ing('eg-torly', 300, 'سلطانية', 'bowl'),
      ing('eg-rice-egyptian-white', 120, '3 أرباع كوب', '3/4 cup'),
    ],
  },
  {
    id: 'white-beans-rice', nameAr: 'فاصوليا بيضا ورز', nameEn: 'White bean stew with rice',
    aliasesAr: ['فاصوليا بيضاء', 'فاصوليا ناشفة'], aliasesEn: ['white beans', 'fasolia beida'],
    category: 'beans', meals: [L, D], goals: [maintain, gain],
    ingredients: [
      ing('eg-fasolia-beida', 300, 'سلطانية', 'bowl'),
      ing('eg-rice-vermicelli', 160, 'كوب', 'cup'),
    ],
  },
  {
    id: 'potato-stew-rice', nameAr: 'بطاطس بالصلصة ورز', nameEn: 'Potato stew with rice',
    aliasesAr: ['بطاطس صلصة', 'بطاطس مطبوخة'], aliasesEn: ['potato stew', 'batates'],
    category: 'stew', meals: [L, D], goals: [maintain],
    ingredients: [
      ing('eg-batates-salsa', 300, 'سلطانية', 'bowl'),
      ing('eg-rice-egyptian-white', 120, '3 أرباع كوب', '3/4 cup'),
    ],
  },
  {
    id: 'moussaka-rice', nameAr: 'مسقعة ورز', nameEn: 'Egyptian moussaka with rice',
    aliasesAr: ['مسقعه', 'مسقعة باذنجان'], aliasesEn: ['moussaka', 'musaqaa'],
    category: 'stew', meals: [L, D], goals: [maintain],
    ingredients: [
      ing('eg-moussaka', 250, 'طبق', 'plate'),
      ing('eg-rice-egyptian-white', 120, '3 أرباع كوب', '3/4 cup'),
    ],
  },
  {
    id: 'macarona-bechamel-plate', nameAr: 'مكرونة بشاميل وسلطة', nameEn: 'Macarona béchamel with salad',
    aliasesAr: ['مكرونه بشاميل', 'بشاميل'], aliasesEn: ['macaroni bechamel', 'pasta bechamel'],
    category: 'pasta', meals: [L, D], goals: [maintain, gain],
    ingredients: [
      ing('eg-macarona-bechamel', 250, 'قطعة', 'piece'),
      ing('eg-salata-baladi', 150, 'طبق', 'bowl'),
    ],
  },
  {
    id: 'kofta-plate', nameAr: 'طبق كفتة مشوية بالطحينة', nameEn: 'Grilled kofta plate with tahini',
    aliasesAr: ['كفته', 'كفتة مشوية'], aliasesEn: ['kofta', 'kefta'],
    category: 'grill', meals: [L, D], goals: [maintain, gain],
    ingredients: [
      ing('eg-kofta', 160, 'سيخين', '2 skewers'),
      ing('eg-tahini-salad', 30, 'ملعقتين', '2 tablespoons'),
      ing('eg-salata-baladi', 150, 'طبق', 'bowl'),
      ing('eg-baladi-bread', 55, 'نص رغيف', 'half loaf'),
    ],
  },
  {
    id: 'kebab-kofta-rice', nameAr: 'كباب وكفتة ورز', nameEn: 'Kebab and kofta with rice',
    aliasesAr: ['كباب', 'مشويات', 'كباب وكفته'], aliasesEn: ['kabab', 'mixed grill'],
    category: 'grill', meals: [L, D], goals: [gain],
    ingredients: [
      ing('eg-kebab', 100, 'سيخ', 'skewer'),
      ing('eg-kofta', 80, 'سيخ', 'skewer'),
      ing('eg-rice-vermicelli', 160, 'كوب', 'cup'),
      ing('eg-salata-baladi', 100, 'طبق صغير', 'small bowl'),
    ],
  },
  {
    id: 'shish-tawook-plate', nameAr: 'شيش طاووق وسلطة', nameEn: 'Shish tawook with salad',
    aliasesAr: ['شيش طاووق', 'شيش طاوق', 'فراخ مشوية مكعبات'], aliasesEn: ['shish taouk', 'chicken skewers'],
    category: 'grill', meals: [L, D], goals: [lose, maintain],
    ingredients: [
      ing('eg-shish-tawook', 240, 'سيخين', '2 skewers'),
      ing('eg-salata-baladi', 150, 'طبق', 'bowl'),
      ing('eg-tahini-salad', 15, 'ملعقة', 'tablespoon'),
    ],
  },
  {
    id: 'grilled-chicken-rice', nameAr: 'ربع فرخة مشوية ورز وسلطة', nameEn: 'Quarter grilled chicken with rice and salad',
    aliasesAr: ['فراخ مشوية', 'فرخة مشويه'], aliasesEn: ['grilled chicken', 'roast chicken'],
    category: 'grill', meals: [L, D], goals: [maintain, gain],
    ingredients: [
      ing('eg-grilled-chicken', 175, 'ربع فرخة', 'quarter chicken'),
      ing('eg-rice-egyptian-white', 160, 'كوب', 'cup'),
      ing('eg-salata-baladi', 150, 'طبق', 'bowl'),
    ],
  },
  {
    id: 'chicken-pane-plate', nameAr: 'فراخ بانيه ورز بالشعرية', nameEn: 'Breaded chicken with vermicelli rice',
    aliasesAr: ['بانيه', 'فراخ بانية'], aliasesEn: ['chicken pane', 'chicken schnitzel'],
    category: 'grill', meals: [L, D], goals: [gain],
    ingredients: [
      ing('eg-chicken-pane', 120, 'قطعة', 'piece'),
      ing('eg-rice-vermicelli', 160, 'كوب', 'cup'),
      ing('eg-salata-baladi', 100, 'طبق صغير', 'small bowl'),
    ],
  },
  {
    id: 'fish-sayadeya', nameAr: 'سمك مشوي ورز صيادية', nameEn: 'Grilled fish with sayadeya rice',
    aliasesAr: ['صياديه', 'سمك صيادية', 'سمك بلطي مشوي'], aliasesEn: ['sayadieh', 'fish and rice'],
    category: 'fish', meals: [L, D], goals: [maintain],
    ingredients: [
      ing('eg-grilled-fish', 200, 'سمكة', 'fish'),
      ing('eg-sayadeya', 250, 'طبق', 'plate'),
      ing('eg-tahini-salad', 30, 'ملعقتين', '2 tablespoons'),
    ],
  },
  {
    id: 'grilled-fish-salad', nameAr: 'سمك مشوي وسلطة خضرا', nameEn: 'Grilled fish with green salad',
    aliasesAr: ['سمك مشوى', 'سمك دايت'], aliasesEn: ['grilled fish', 'fish salad'],
    category: 'fish', meals: [L, D], goals: [lose],
    ingredients: [
      ing('eg-grilled-fish', 200, 'سمكة', 'fish'),
      ing('eg-salata-baladi', 150, 'طبق', 'bowl'),
      ing('usda-lemon', 15, 'نص ليمونة', 'half a lemon'),
    ],
  },
  {
    id: 'fried-tilapia-plate', nameAr: 'بلطي مقلي ورز وطحينة', nameEn: 'Fried tilapia with rice and tahini',
    aliasesAr: ['سمك مقلي', 'بلطى'], aliasesEn: ['fried fish', 'tilapia'],
    category: 'fish', meals: [L, D], goals: [gain],
    ingredients: [
      ing('eg-fried-tilapia', 250, 'سمكة', 'fish'),
      ing('eg-rice-egyptian-white', 160, 'كوب', 'cup'),
      ing('eg-tahini-salad', 30, 'ملعقتين', '2 tablespoons'),
    ],
  },
  {
    id: 'liver-sandwiches', nameAr: 'ساندوتشين كبدة إسكندراني', nameEn: 'Two Alexandrian liver sandwiches',
    aliasesAr: ['كبده', 'كبدة اسكندراني', 'سندوتش كبدة'], aliasesEn: ['liver sandwich', 'kebda'],
    category: 'bread', meals: [L, D], goals: [maintain, gain],
    ingredients: [ing('eg-liver-sandwich', 360, 'ساندوتشين', '2 sandwiches')],
  },
  {
    id: 'hawawshi-plate', nameAr: 'حواوشي', nameEn: 'Hawawshi',
    aliasesAr: ['حواوشى', 'عيش باللحمة'], aliasesEn: ['hawawshy', 'meat stuffed bread'],
    category: 'bread', meals: [L, D], goals: [gain],
    ingredients: [
      ing('eg-hawawshi', 250, 'رغيف', 'loaf'),
      ing('eg-torshi', 30, 'قطعة مخلل', 'piece of pickle'),
    ],
  },
  {
    id: 'shawarma-sandwich', nameAr: 'ساندوتش شاورما فراخ', nameEn: 'Chicken shawarma sandwich',
    aliasesAr: ['شاورمه', 'شاورما'], aliasesEn: ['shawarma', 'shawerma'],
    category: 'bread', meals: [L, D], goals: [maintain],
    ingredients: [ing('eg-shawerma-chicken-sandwich', 250, 'ساندوتش', 'sandwich')],
  },
  {
    id: 'shawarma-plate', nameAr: 'طبق شاورما فراخ بالسلطة', nameEn: 'Chicken shawarma plate with salad',
    aliasesAr: ['شاورما فراخ طبق', 'شاورمه بدون عيش'], aliasesEn: ['shawarma plate', 'shawarma bowl'],
    category: 'grill', meals: [L, D], goals: [lose, maintain],
    ingredients: [
      ing('eg-shawerma-chicken-plate', 250, 'طبق', 'plate'),
      ing('eg-salata-baladi', 100, 'طبق صغير', 'small bowl'),
      ing('eg-tahini-salad', 15, 'ملعقة', 'tablespoon'),
    ],
  },
  {
    id: 'lentil-soup-bowl', nameAr: 'شوربة عدس بالليمون', nameEn: 'Lentil soup with lemon',
    aliasesAr: ['شوربه عدس', 'عدس أصفر'], aliasesEn: ['lentil soup', 'shorbet ads'],
    category: 'soup', meals: [L, D], goals: [lose, maintain],
    ingredients: [
      ing('eg-lentil-soup', 300, 'سلطانية', 'bowl'),
      ing('eg-baladi-bread', 55, 'نص رغيف', 'half loaf'),
      ing('usda-lemon', 15, 'نص ليمونة', 'half a lemon'),
    ],
  },
  {
    id: 'orzo-soup-chicken', nameAr: 'شوربة لسان عصفور بالفراخ', nameEn: 'Orzo soup with chicken',
    aliasesAr: ['لسان عصفور', 'شوربه لسان عصفور'], aliasesEn: ['orzo soup', 'chicken soup'],
    category: 'soup', meals: [L, D], goals: [lose, maintain],
    ingredients: [
      ing('eg-orzo-soup', 300, 'سلطانية', 'bowl'),
      ing('usda-chicken-breast-roasted', 100, 'قطعة صدر', 'piece of breast'),
    ],
  },
  {
    id: 'freekeh-chicken-plate', nameAr: 'فريك بالفراخ', nameEn: 'Freekeh with chicken',
    aliasesAr: ['فريكة', 'فريك'], aliasesEn: ['freekah', 'frikeh'],
    category: 'rice', meals: [L, D], goals: [maintain],
    ingredients: [ing('eg-freekeh-chicken', 300, 'طبق', 'plate')],
  },
  {
    id: 'roz-meammar-plate', nameAr: 'رز معمر', nameEn: "Roz me'ammar (baked rice)",
    aliasesAr: ['أرز معمر', 'رز معمّر بالفرن'], aliasesEn: ['baked rice', 'roz meamar'],
    category: 'rice', meals: [L, D], goals: [gain],
    ingredients: [ing('eg-roz-meammar', 250, 'طاجن صغير', 'small casserole')],
  },
  {
    id: 'hamam-mahshi-plate', nameAr: 'حمام محشي', nameEn: 'Stuffed pigeon',
    aliasesAr: ['حمام محشى فريك', 'حمامة'], aliasesEn: ['hamam mahshi', 'pigeon'],
    category: 'grill', meals: [L, D], goals: [gain],
    ingredients: [
      ing('eg-hamam-mahshi', 300, 'حمامة', 'pigeon'),
      ing('eg-salata-baladi', 100, 'طبق صغير', 'small bowl'),
    ],
  },
  {
    id: 'mujaddara-salad', nameAr: 'مجدرة وسلطة', nameEn: 'Mujaddara with salad',
    aliasesAr: ['مجدره', 'رز بالعدس', 'كشري أصفر'], aliasesEn: ['mujadara', 'lentils and rice'],
    category: 'rice', meals: [L, D], goals: [lose, maintain],
    ingredients: [
      ing('eg-mujaddara', 250, 'طبق', 'plate'),
      ing('eg-salata-baladi', 150, 'طبق', 'bowl'),
    ],
  },
  {
    id: 'kishk-bowl', nameAr: 'كشك صعيدي', nameEn: 'Kishk',
    aliasesAr: ['كشك', 'كشك بالفراخ'], aliasesEn: ['kishk soup'],
    category: 'soup', meals: [L, D], goals: [maintain],
    ingredients: [
      ing('eg-kishk', 250, 'سلطانية', 'bowl'),
      ing('eg-baladi-bread', 55, 'نص رغيف', 'half loaf'),
    ],
  },

  // ── Arab classics ──────────────────────────────────────────────────────────────────────
  {
    id: 'kabsa-chicken-plate', nameAr: 'كبسة دجاج', nameEn: 'Chicken kabsa',
    aliasesAr: ['كبسه', 'كبسة فراخ', 'كبسة'], aliasesEn: ['kabsa', 'machboos'],
    category: 'rice', meals: [L, D], goals: [maintain, gain],
    ingredients: [
      ing('eg-kabsa-chicken', 400, 'طبق', 'plate'),
      ing('eg-salata-baladi', 100, 'طبق صغير', 'small bowl'),
    ],
  },
  {
    id: 'mandi-lamb-plate', nameAr: 'مندي لحم', nameEn: 'Lamb mandi',
    aliasesAr: ['مندى', 'مندي'], aliasesEn: ['mandi', 'lamb and rice'],
    category: 'rice', meals: [L, D], goals: [gain],
    ingredients: [ing('eg-mandi-lamb', 400, 'طبق', 'plate')],
  },
  {
    id: 'maqluba-plate', nameAr: 'مقلوبة بالزبادي', nameEn: 'Maqluba with yogurt',
    aliasesAr: ['مقلوبه', 'مقلوبة باذنجان'], aliasesEn: ['maqlooba', 'makluba'],
    category: 'rice', meals: [L, D], goals: [maintain, gain],
    ingredients: [
      ing('eg-maqluba', 350, 'طبق', 'plate'),
      ing('usda-yogurt-plain', 100, 'نص علبة زبادي', 'half tub of yogurt'),
    ],
  },
  {
    id: 'fattoush', nameAr: 'فتوش', nameEn: 'Fattoush salad',
    aliasesAr: ['سلطة فتوش', 'فتّوش'], aliasesEn: ['fatoush', 'bread salad'],
    category: 'salad', meals: [L, D], goals: [lose],
    ingredients: [
      ing('usda-lettuce', 100, 'كوبين خس', '2 cups lettuce'),
      ing('usda-tomato', 100, 'طماطماية صغيرة', 'small tomato'),
      ing('usda-cucumber', 100, 'خيارة', 'cucumber'),
      ing('usda-radish', 30, '3 فجلات', '3 radishes'),
      ing('usda-pita-white', 30, 'نص رغيف محمص', 'half a toasted pita'),
      ing('usda-olive-oil', 13.5, 'ملعقة كبيرة', 'tablespoon'),
      ing('usda-lemon', 15, 'نص ليمونة', 'half a lemon'),
    ],
  },
  {
    id: 'tabbouleh', nameAr: 'تبولة', nameEn: 'Tabbouleh',
    aliasesAr: ['تبوله', 'سلطة بقدونس وبرغل'], aliasesEn: ['tabouli', 'tabbouli'],
    category: 'salad', meals: [L, D, S], goals: [lose],
    ingredients: [
      ing('usda-parsley', 80, 'حزمة بقدونس', 'bunch of parsley'),
      ing('usda-bulgur-cooked', 60, 'ربع كوب', 'quarter cup'),
      ing('usda-tomato', 100, 'طماطماية صغيرة', 'small tomato'),
      ing('usda-onion', 20, 'ملعقة بصل مفروم', 'tablespoon of onion'),
      ing('usda-olive-oil', 13.5, 'ملعقة كبيرة', 'tablespoon'),
      ing('usda-lemon', 30, 'ليمونة', 'lemon'),
    ],
  },
  {
    id: 'kibbeh-plate', nameAr: 'كبيبة مع حمص', nameEn: 'Kibbeh with hummus',
    aliasesAr: ['كبة', 'كبيبه'], aliasesEn: ['kibbe', 'kobeba'],
    category: 'grill', meals: [L, D, S], goals: [maintain],
    ingredients: [
      ing('eg-kobeba', 180, '3 أصابع', '3 pieces'),
      ing('eg-hummus', 60, '2 ملعقة', '2 tablespoons'),
      ing('eg-salata-baladi', 100, 'طبق صغير', 'small bowl'),
    ],
  },
  {
    id: 'baba-ghanoug-plate', nameAr: 'بابا غنوج بالعيش الشامي', nameEn: 'Baba ghanoush with pita',
    aliasesAr: ['بابا غنوج', 'متبل', 'باباغنوج'], aliasesEn: ['baba ganoush', 'mutabbal'],
    category: 'salad', meals: [D, S], goals: [lose, maintain],
    ingredients: [
      ing('eg-baba-ghanoug', 100, 'طبق صغير', 'small bowl'),
      ing('usda-pita-white', 60, 'رغيف', 'loaf'),
      ing('usda-cucumber', 100, 'خيارة', 'cucumber'),
    ],
  },

  // ── Everyday healthy meals ─────────────────────────────────────────────────────────────
  {
    id: 'chicken-brown-rice', nameAr: 'صدور فراخ مشوية ورز بني وبروكلي', nameEn: 'Grilled chicken breast, brown rice and broccoli',
    aliasesAr: ['صدر فراخ', 'وجبة دايت', 'فراخ ورز بني'], aliasesEn: ['chicken and rice', 'meal prep chicken'],
    category: 'grill', meals: [L, D], goals: [lose, maintain],
    ingredients: [
      ing('usda-chicken-breast-roasted', 150, 'صدر صغير', 'small breast'),
      ing('usda-rice-brown-cooked', 150, '3 أرباع كوب', '3/4 cup'),
      ing('usda-broccoli', 150, 'كوب ونص', '1½ cups'),
      ing('usda-olive-oil', 5, 'ملعقة صغيرة', 'teaspoon'),
    ],
  },
  {
    id: 'tuna-salad', nameAr: 'سلطة تونة بالذرة', nameEn: 'Tuna and corn salad',
    aliasesAr: ['تونه', 'سلطة تونه'], aliasesEn: ['tuna salad'],
    category: 'salad', meals: [L, D], goals: [lose],
    ingredients: [
      ing('usda-tuna-water', 120, 'علبة', 'can'),
      ing('usda-lettuce', 100, 'كوبين خس', '2 cups lettuce'),
      ing('usda-tomato', 100, 'طماطماية صغيرة', 'small tomato'),
      ing('usda-cucumber', 100, 'خيارة', 'cucumber'),
      ing('usda-corn', 50, '3 ملاعق', '3 tablespoons'),
      ing('usda-olive-oil', 7, 'نص ملعقة', 'half tablespoon'),
      ing('usda-lemon', 15, 'نص ليمونة', 'half a lemon'),
    ],
  },
  {
    id: 'salmon-sweet-potato', nameAr: 'سلمون وبطاطا وجرجير', nameEn: 'Salmon with sweet potato and arugula',
    aliasesAr: ['سالمون', 'سمك سلمون'], aliasesEn: ['salmon dinner'],
    category: 'fish', meals: [L, D], goals: [maintain],
    ingredients: [
      ing('usda-salmon-cooked', 150, 'قطعة', 'fillet'),
      ing('usda-sweet-potato-baked', 200, 'بطاطاية وسط', 'medium sweet potato'),
      ing('usda-arugula', 50, 'حزمة صغيرة', 'small bunch'),
      ing('usda-olive-oil', 5, 'ملعقة صغيرة', 'teaspoon'),
    ],
  },
  {
    id: 'turkey-sandwich', nameAr: 'ساندوتش ديك رومي بالتوست الأسمر', nameEn: 'Turkey sandwich on whole-wheat toast',
    aliasesAr: ['تيركي', 'ساندوتش رومي'], aliasesEn: ['turkey sandwich'],
    category: 'bread', meals: [B, L, S], goals: [lose, maintain],
    ingredients: [
      ing('usda-bread-wholewheat', 64, 'شريحتين توست', '2 slices of toast'),
      ing('usda-turkey-breast-roasted', 80, '4 شرائح', '4 slices'),
      ing('usda-lettuce', 20, 'ورقتين خس', '2 lettuce leaves'),
      ing('usda-tomato', 40, '3 شرائح طماطم', '3 tomato slices'),
      ing('usda-cheese-mozzarella', 28, 'شريحة', 'slice'),
    ],
  },
  {
    id: 'chickpea-salad', nameAr: 'سلطة حمص الشام', nameEn: 'Chickpea salad',
    aliasesAr: ['حمص شام', 'سلطة حمص'], aliasesEn: ['chickpea salad', 'garbanzo salad'],
    category: 'salad', meals: [L, D, S], goals: [lose, maintain],
    ingredients: [
      ing('usda-chickpeas-cooked', 150, 'كوب', 'cup'),
      ing('usda-cucumber', 100, 'خيارة', 'cucumber'),
      ing('usda-tomato', 100, 'طماطماية صغيرة', 'small tomato'),
      ing('usda-parsley', 10, 'ملعقة بقدونس', 'tablespoon of parsley'),
      ing('usda-olive-oil', 7, 'نص ملعقة', 'half tablespoon'),
      ing('usda-lemon', 15, 'نص ليمونة', 'half a lemon'),
    ],
  },
  {
    id: 'steak-potato', nameAr: 'ستيك لحم وبطاطس بالفرن', nameEn: 'Beef steak with baked potato',
    aliasesAr: ['ستيك', 'لحمة مشوية'], aliasesEn: ['steak dinner'],
    category: 'grill', meals: [L, D], goals: [gain, maintain],
    ingredients: [
      ing('usda-beef-steak', 150, 'قطعة', 'steak'),
      ing('usda-potato-baked', 200, 'بطاطساية كبيرة', 'large potato'),
      ing('eg-salata-baladi', 150, 'طبق', 'bowl'),
    ],
  },
  {
    id: 'pasta-beef', nameAr: 'مكرونة باللحمة المفرومة والصلصة', nameEn: 'Pasta with lean beef and tomato sauce',
    aliasesAr: ['مكرونه باللحمة', 'مكرونة بولونيز'], aliasesEn: ['bolognese', 'beef pasta'],
    category: 'pasta', meals: [L, D], goals: [gain],
    ingredients: [
      ing('usda-pasta-cooked', 250, 'طبق', 'plate'),
      ing('usda-beef-ground-lean-cooked', 100, 'نص كوب', 'half cup'),
      ing('usda-tomato-paste', 30, 'ملعقتين صلصة', '2 tablespoons of paste'),
      ing('usda-olive-oil', 7, 'نص ملعقة', 'half tablespoon'),
    ],
  },
  {
    id: 'shrimp-rice', nameAr: 'جمبري مشوي ورز', nameEn: 'Grilled shrimp with rice',
    aliasesAr: ['جمبرى', 'جمبري'], aliasesEn: ['shrimp and rice', 'prawns'],
    category: 'fish', meals: [L, D], goals: [lose, maintain],
    ingredients: [
      ing('usda-shrimp-cooked', 150, '12 حباية', '12 shrimp'),
      ing('usda-rice-white-cooked', 158, 'كوب', 'cup'),
      ing('eg-salata-baladi', 100, 'طبق صغير', 'small bowl'),
    ],
  },
  {
    id: 'egg-veg-wrap', nameAr: 'راب بيض بالخضار', nameEn: 'Egg and vegetable wrap',
    aliasesAr: ['راب بيض', 'لفافة بيض'], aliasesEn: ['egg wrap'],
    category: 'eggs', meals: [B, D], goals: [lose, maintain],
    ingredients: [
      ing('usda-pita-wholewheat', 64, 'رغيف', 'loaf'),
      ing('usda-egg-omelet', 120, 'بيضتين', '2 eggs'),
      ing('usda-pepper-green', 50, 'نص فلفلاية', 'half a pepper'),
      ing('usda-tomato', 60, 'نص طماطماية', 'half a tomato'),
    ],
  },

  // ── Snacks and desserts ────────────────────────────────────────────────────────────────
  {
    id: 'dates-milk', nameAr: 'بلح ولبن', nameEn: 'Dates with milk',
    aliasesAr: ['تمر ولبن', 'بلح باللبن', 'سحور'], aliasesEn: ['dates and milk', 'suhoor'],
    category: 'fruit', meals: [B, S], goals: [maintain, gain],
    ingredients: [
      ing('usda-dates-deglet', 50, '7 بلحات', '7 dates'),
      ing('usda-milk-lowfat', 244, 'كوب', 'cup'),
    ],
  },
  {
    id: 'apple-peanut-butter', nameAr: 'تفاح بزبدة الفول السوداني', nameEn: 'Apple with peanut butter',
    aliasesAr: ['تفاحة', 'تفاح وزبدة فول'], aliasesEn: ['apple pb'],
    category: 'fruit', meals: [S], goals: [lose, maintain],
    ingredients: [
      ing('usda-apple', 182, 'تفاحة وسط', 'medium apple'),
      ing('usda-peanut-butter', 16, 'ملعقة', 'tablespoon'),
    ],
  },
  {
    id: 'nuts-raisins', nameAr: 'مكسرات وزبيب', nameEn: 'Nuts and raisins',
    aliasesAr: ['ياميش', 'لوز وعين جمل', 'مكسرات'], aliasesEn: ['trail mix', 'mixed nuts'],
    category: 'snack', meals: [S], goals: [maintain, gain],
    ingredients: [
      ing('usda-almonds', 15, '10 حبات لوز', '10 almonds'),
      ing('usda-walnuts', 10, '3 أنصاص عين جمل', '3 walnut halves'),
      ing('usda-raisins', 15, 'ملعقة كبيرة', 'tablespoon'),
    ],
  },
  {
    id: 'fruit-salad', nameAr: 'سلطة فواكه', nameEn: 'Fruit salad',
    aliasesAr: ['فاكهة مشكلة', 'سلطه فواكه'], aliasesEn: ['fruit bowl'],
    category: 'fruit', meals: [B, S], goals: [lose, maintain],
    ingredients: [
      ing('usda-apple', 100, 'نص تفاحة', 'half an apple'),
      ing('usda-banana', 60, 'نص موزة', 'half a banana'),
      ing('usda-orange', 130, 'برتقالة', 'orange'),
      ing('usda-strawberry', 100, '7 حبات', '7 berries'),
    ],
  },
  {
    id: 'yogurt-cucumber', nameAr: 'زبادي بالخيار والنعناع', nameEn: 'Yogurt with cucumber and mint',
    aliasesAr: ['زبادي بالخيار', 'سلطة زبادي'], aliasesEn: ['cucumber yogurt', 'tzatziki style'],
    category: 'dairy', meals: [S, D], goals: [lose],
    ingredients: [
      ing('usda-yogurt-plain', 170, 'علبة', 'tub'),
      ing('usda-cucumber', 100, 'خيارة', 'cucumber'),
    ],
  },
  {
    id: 'popcorn-snack', nameAr: 'فشار', nameEn: 'Air-popped popcorn',
    aliasesAr: ['فشار بدون زيت', 'بوب كورن'], aliasesEn: ['popcorn'],
    category: 'snack', meals: [S], goals: [lose],
    ingredients: [ing('usda-popcorn', 25, '3 أكواب', '3 cups')],
  },
  {
    id: 'guava-orange', nameAr: 'جوافة وبرتقالة', nameEn: 'Guava and an orange',
    aliasesAr: ['جوافه', 'فاكهة'], aliasesEn: ['guava', 'fruit snack'],
    category: 'fruit', meals: [S], goals: [lose, maintain],
    ingredients: [
      ing('usda-guava', 110, 'جوافتين', '2 guavas'),
      ing('usda-orange', 131, 'برتقالة', 'orange'),
    ],
  },
  {
    id: 'roz-bel-laban-cup', nameAr: 'رز بلبن', nameEn: 'Rice pudding',
    aliasesAr: ['ارز باللبن', 'رز باللبن'], aliasesEn: ['roz bel laban', 'rice pudding'],
    category: 'sweet', meals: [S], goals: [maintain],
    ingredients: [ing('eg-roz-bel-laban', 200, 'كوب', 'cup')],
  },
  {
    id: 'mahalabeya-cup', nameAr: 'مهلبية', nameEn: 'Mahalabia',
    aliasesAr: ['مهلبيه', 'محلبية'], aliasesEn: ['muhallebi', 'milk pudding'],
    category: 'sweet', meals: [S], goals: [maintain],
    ingredients: [ing('eg-mahalabeya', 180, 'كوب', 'cup')],
  },
  {
    id: 'basbousa-piece', nameAr: 'قطعة بسبوسة', nameEn: 'Basbousa',
    aliasesAr: ['بسبوسه', 'هريسة'], aliasesEn: ['basbousa', 'semolina cake'],
    category: 'sweet', meals: [S], goals: [gain],
    ingredients: [ing('eg-basbousa', 70, 'قطعة', 'piece')],
  },
  {
    id: 'om-ali-bowl', nameAr: 'أم علي', nameEn: 'Om Ali',
    aliasesAr: ['ام علي', 'أم على'], aliasesEn: ['umm ali', 'om ali'],
    category: 'sweet', meals: [S], goals: [gain],
    ingredients: [ing('eg-om-ali', 250, 'طاجن', 'bowl')],
  },
  {
    id: 'sahlab-nuts', nameAr: 'سحلب بالمكسرات', nameEn: 'Sahlab with nuts',
    aliasesAr: ['سحلب', 'سحلب ساخن'], aliasesEn: ['salep', 'sahlab'],
    category: 'drink', meals: [S], goals: [maintain, gain],
    ingredients: [
      ing('eg-sahlab', 250, 'كوب', 'cup'),
      ing('usda-almonds', 10, 'ملعقة لوز مجروش', 'tablespoon of crushed almonds'),
    ],
  },
  {
    id: 'qatayef-pieces', nameAr: 'قطايف (قطعتين)', nameEn: 'Qatayef (two pieces)',
    aliasesAr: ['قطايف', 'قطائف'], aliasesEn: ['atayef', 'qatayef'],
    category: 'sweet', meals: [S], goals: [gain],
    ingredients: [ing('eg-qatayef', 120, 'قطعتين', '2 pieces')],
  },
];
