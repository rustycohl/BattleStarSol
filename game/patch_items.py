import json

with open('data/items.json', 'r') as f:
    items = json.load(f)

for k, v in items.items():
    skills = v.get('skills', [])
    if 'primitive' in skills or 'ballistic' in skills:
        v['damage_type'] = 'kinetic'
        v['armor_pierce'] = 1 if 'ballistic' in skills else 0
        if 'sniper' in skills: v['armor_pierce'] = 2
    elif 'laser' in skills:
        v['damage_type'] = 'thermal'
        v['armor_pierce'] = 2
    elif 'magnetic' in skills:
        v['damage_type'] = 'rail'
        v['armor_pierce'] = 5
    elif 'plasma' in skills:
        v['damage_type'] = 'thermal'
        v['armor_pierce'] = 6
    elif 'beam' in skills:
        v['damage_type'] = 'rail'
        v['armor_pierce'] = 10
    else:
        v['damage_type'] = 'kinetic'
        v['armor_pierce'] = 0

with open('data/items.json', 'w') as f:
    json.dump(items, f, indent=2)
