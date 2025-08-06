#!/usr/bin/env python3

import csv

# Read 'organisasjonsnummer' from 'enheter.csv' into a set
with open('enheter.csv', newline='', encoding='utf-8') as enheter_file:
    enheter_reader = csv.DictReader(enheter_file)
    enheter_orgnums = set(row['organisasjonsnummer'] for row in enheter_reader)

# Open 'underenheter.csv' and filter out inconsistent lines
with open('underenheter.csv', newline='', encoding='utf-8') as underenheter_file, \
     open('underenheter_filtered.csv', 'w', newline='', encoding='utf-8') as output_file:
    underenheter_reader = csv.DictReader(underenheter_file)
    fieldnames = underenheter_reader.fieldnames
    writer = csv.DictWriter(output_file, fieldnames=fieldnames)
    writer.writeheader()
    for row in underenheter_reader:
        if row['overordnetEnhet'] in enheter_orgnums:
            writer.writerow(row)

