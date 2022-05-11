import zipfile
import json
import sys
import os.path


print("Hello World Fucker")

ILLEGAL_PATH_CHARACTERS = {'<', '>', ':', '/', '\\', '|', '?', '*', '(', ')'}




def parse_json(json_struct):
    for key in ['config', 'filters', 'query', 'dataTransforms']:
        if key in json_struct.keys():
            json_struct[key] = json.loads(json_struct[key])
    return json_struct


def main():
    separator = sys.argv[2]
    file_list = sys.argv[1].split(separator)
    for file in file_list:

        if file.endswith('.json') and os.path.exists(file):
            with open(file, 'r', encoding='utf-8-sig') as f:
                json_str = json.dumps(json.load(f), indent=4)
            with open(file, 'w') as f:
                f.write(json_str)
            print('Pretty Printed {}'.format(file))

        if (file.endswith('.pbix') or file.endswith('.pbit')) and os.path.exists(file):

            json_dir_path = file[:-5]


            os.makedirs(json_dir_path, exist_ok=True)
            for f in os.listdir(json_dir_path):
                os.remove(os.path.join(json_dir_path, f))

            zf = zipfile.ZipFile(file)
            data = json.loads(zf.read('Report/Layout').decode('utf-16-le'))
            data['config'] = json.loads(data['config'])
            if 'filters' in data:
                data['filters'] = json.loads(data['filters'])


            sections = data.pop('sections')
            for section in sections:
                parse_json(section)
                for visual_container in section['visualContainers']:
                    parse_json(visual_container)
                section_name = section['displayName'].translate({ord(x): ' ' for x in ILLEGAL_PATH_CHARACTERS})
                output_path = json_dir_path + '/' + section_name + '.json'
                with open(output_path, "w") as f:
                    json.dump(section, f, indent=4)


            file_name = os.path.basename(file)[:-5]
            with open(json_dir_path + '/' + file_name + '.json', "w") as f:
                json.dump(data, f, indent=4)

            print('Pretty Printed {}'.format(file))


if __name__ == '__main__':
    main()
