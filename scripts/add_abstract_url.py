import json, re

def add_abstract_url(data_path):
    with open(data_path, 'r', encoding='utf-8-sig') as f:
        data = json.load(f)

    changed = False
    for article in data['articles']:
        if article.get('category') == 'paper':
            url = article.get('url', '')
            m = re.match(r'https://arxiv\.org/pdf/(\d+\.\d+)(?:v\d+)?\.pdf', url)
            if m:
                arxiv_id = m.group(1)
                abstract_url = f'https://arxiv.org/abs/{arxiv_id}'
                if article.get('abstractUrl') != abstract_url:
                    article['abstractUrl'] = abstract_url
                    changed = True
                    print(f'  Added abstractUrl: {abstract_url}')

    if changed:
        with open(data_path, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        print(f'Updated {data_path}')
    else:
        print(f'No changes needed for {data_path}')

add_abstract_url('data/articles.json')
add_abstract_url('data/archive/2026-07-07.json')
add_abstract_url('data/archive/2026-07-06.json')
