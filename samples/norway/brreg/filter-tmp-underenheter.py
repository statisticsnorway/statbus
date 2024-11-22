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

prompt_o1_preview = """
I have two files on my macOS with Homebrew.

```
enheter.csv
underenheter.csv
```

Here are the structures
`head enheter.csv | pbcopy`

```
"organisasjonsnummer","navn","organisasjonsform.kode","organisasjonsform.beskrivelse","naeringskode1.kode","naeringskode1.beskrivelse","naeringskode2.kode","naeringskode2.beskrivelse","naeringskode3.kode","naeringskode3.beskrivelse","hjelpeenhetskode.kode","hjelpeenhetskode.beskrivelse","harRegistrertAntallAnsatte","antallAnsatte","hjemmeside","postadresse.adresse","postadresse.poststed","postadresse.postnummer","postadresse.kommune","postadresse.kommunenummer","postadresse.land","postadresse.landkode","forretningsadresse.adresse","forretningsadresse.poststed","forretningsadresse.postnummer","forretningsadresse.kommune","forretningsadresse.kommunenummer","forretningsadresse.land","forretningsadresse.landkode","institusjonellSektorkode.kode","institusjonellSektorkode.beskrivelse","sisteInnsendteAarsregnskap","registreringsdatoenhetsregisteret","stiftelsesdato","registrertIMvaRegisteret","frivilligMvaRegistrertBeskrivelser","registrertIFrivillighetsregisteret","registrertIForetaksregisteret","registrertIStiftelsesregisteret","konkurs","konkursdato","underAvvikling","underAvviklingDato","underTvangsavviklingEllerTvangsopplosning","tvangsopplostPgaManglendeDagligLederDato","tvangsopplostPgaManglendeRevisorDato","tvangsopplostPgaManglendeRegnskapDato","tvangsopplostPgaMangelfulltStyreDato","tvangsavvikletPgaManglendeSlettingDato","overordnetEnhet","maalform","vedtektsdato","vedtektsfestetFormaal","aktivitet"
"810034882","SANDNES ELEKTRISKE AS","AS","Aksjeselskap","43.210","Elektrisk installasjonsarbeid","27.510","Produksjon av elektriske husholdningsmaskiner og -apparater","","","","","true","11","","Postboks 32","SANDNES","4301","SANDNES","1108","Norge","NO","Langgata 87","SANDNES","4306","SANDNES","1108","Norge","NO","2100","Private aksjeselskaper mv.","2022","1995-02-19","1977-06-15","true","","false","true","false","false","","false","","false","","","","","","","Bokmål","2023-12-29","Drive handel, installasjons og servicevirksomhet, eller annen virksomhet forbundet med dette, samt delta i annen virksomhet.","Handel og innstallasjonsvirksomhet, eller annen virksomhet forbundet med dette, samt delta I annen virksomhet."
"810059672","AASEN & FARSTAD AS","AS","Aksjeselskap","68.209","Utleie av egen eller leid fast eiendom ellers","","","","","","","false","","","","","","","","","","Sjøgardsvegen 8","EIDSVÅG I ROMSDAL","6460","MOLDE","1506","Norge","NO","2100","Private aksjeselskaper mv.","2023","1995-02-19","1965-06-26","false","","false","true","false","false","","false","","false","","","","","","","Bokmål","1997-01-20","Utleievirksomhet, fortrinnsvis av forretnings- eiendommer.","Utleie av forretningseiendommer."
"810093382","BRIS EIENDOM AS","AS","Aksjeselskap","68.209","Utleie av egen eller leid fast eiendom ellers","","","","","","","false","","","","","","","","","","c/o BDO AS/nFjellgata 6","KRISTIANSAND S","4612","KRISTIANSAND","4204","Norge","NO","2100","Private aksjeselskaper mv.","2022","1995-02-19","1974-10-23","false","","false","true","false","false","","false","","false","","","","","","","Bokmål","2018-11-23","Eie og drift av fast eiendom og annen økonomisk virksomhet som står i naturlig forbindelse med dette. Videre kan selskapet i egen regi eller gjennom andre selskaper foreta investeringer i aksjer i aksjemarkedet.","Eie og drift av fast eiendom, investering i aksjer."
"810094532","AGDERPOSTEN MEDIER AS","AS","Aksjeselskap","68.209","Utleie av egen eller leid fast eiendom ellers","","","","","70.100","Hovedkontortjenester","false","","","","","","","","","","Østre gate 3","ARENDAL","4836","ARENDAL","4203","Norge","NO","2100","Private aksjeselskaper mv.","2023","1995-03-12","1919-09-18","true","Utleier av bygg eller anlegg","false","true","false","false","","false","","false","","","","","","","Bokmål","2024-03-01","Drive virksomhet innenfor investeringer i og forvaltning av eiendom og andre formuesgjenstander.","Holdingselskap."
"810098252","ODD FELLOW HUSET BODØ AS","AS","Aksjeselskap","68.209","Utleie av egen eller leid fast eiendom ellers","","","","","","","true","","","Postboks 241","BODØ","8001","BODØ","1804","Norge","NO","Reinslettveien 2","BODØ","8009","BODØ","1804","Norge","NO","2100","Private aksjeselskaper mv.","2022","1995-02-19","1974-06-10","false","","true","true","false","false","","false","","false","","","","","","","Bokmål","2012-10-07","Skaffe Odd Fellow Ordenen i Bodø tjenelige lokaler ved å erverve, oppføre ller leie fast eiendom. Selskapet kan støtte selskaper og institusjoner tilhørende eller tilknyttet Odd Fellow Ordenen ved å yte lån eller tegne aksjer. Det kan ikke utdeles utbytte. Salg av hele eller deler av fast eiendom tilhørende selskapet skal godkjennes av Den Uavhængige Norske Storloge av Odd Fellow Ordenen. Videre skal lov for Loger § 16-8 og tilhørende forskrifter til loven følges.","Ved anskaffelse og drift av fast eiendom å skaffe Odd Fellow-ordenen i Bodø tjenelige lokaler og hva som står i forbindelse hermed."
"810105372","SØRLANDSPORTEN EIENDOM AS","AS","Aksjeselskap","68.209","Utleie av egen eller leid fast eiendom ellers","","","","","","","false","","","","","","","","","","","AKLAND","4994","RISØR","4201","Norge","NO","2100","Private aksjeselskaper mv.","2023","1995-03-12","1973-12-14","true","Utleier av bygg eller anlegg","false","true","false","false","","false","","false","","","","","","","Bokmål","2003-03-26","Eie og forvalte fast eiendom og annen økonomisk virksomhet som naturlig står i forbindelse med dette.","Eie og forvalte fast eiendom og annen økonomisk virksomhet som naturlig står i forbindelse med dette."
"810130822","ALSTRA AS","AS","Aksjeselskap","46.739","Engroshandel med byggevarer ikke nevnt annet sted","","","","","","","true","","","Søndeledveien 805","SØNDELED","4990","RISØR","4201","Norge","NO","Homme","SØNDELED","4990","RISØR","4201","Norge","NO","2100","Private aksjeselskaper mv.","2022","1995-03-12","1973-12-17","true","","false","true","false","false","","false","","false","","","","","","","Bokmål","2002-04-20","Produksjon og salg, samt hva dermed står i for- bindelse. Selskapet kan også engasjere seg i andre foretagender.","Produksjon og salg, samt hva dermed står i for- bindelse. Selskapet kan også engasjere seg i andre foretagender."
"810182482","FAGMØBLER HERMAN ANDERSEN AS","AS","Aksjeselskap","47.591","Butikkhandel med møbler","","","","","","","true","9","","","","","","","","","Bergemoveien 40","GRIMSTAD","4886","GRIMSTAD","4202","Norge","NO","2100","Private aksjeselskaper mv.","2022","1995-02-19","1976-05-14","true","","false","true","false","false","","false","","false","","","","","","","Bokmål","2003-11-24","Salg av møbler og alt som hermed står i forbindelse.","Salg av møbler og alt som hermed står i forbindelse."
"810202572","BORTIGARD AS","AS","Aksjeselskap","41.200","Oppføring av bygninger","","","","","70.100","Hovedkontortjenester","false","","","","","","","","","","Løkkeveien 18","HOLMESTRAND","3085","HOLMESTRAND","3903","Norge","NO","2100","Private aksjeselskaper mv.","2022","1995-02-19","1975-06-04","true","","false","true","false","false","","false","","false","","","","","","","Bokmål","2018-06-27","Drive utleie av fast eiendom, maskiner og utstyr, samt kjøp og salg av aksjer.","Drive utleie av fast eiendom, maskiner og utstyr, samt kjøp og salg av aksjer."
```

`head underenheter.csv| pbcopy`
```
organisasjonsnummer,navn,overordnetEnhet,organisasjonsform.kode,organisasjonsform.beskrivelse,naeringskode1.kode,naeringskode1.beskrivelse,naeringskode2.kode,naeringskode2.beskrivelse,naeringskode3.kode,naeringskode3.beskrivelse,hjelpeenhetskode.kode,hjelpeenhetskode.beskrivelse,harRegistrertAntallAnsatte,antallAnsatte,hjemmeside,postadresse.adresse,postadresse.poststed,postadresse.postnummer,postadresse.kommune,postadresse.kommunenummer,postadresse.land,postadresse.landkode,beliggenhetsadresse.adresse,beliggenhetsadresse.poststed,beliggenhetsadresse.postnummer,beliggenhetsadresse.kommune,beliggenhetsadresse.kommunenummer,beliggenhetsadresse.land,beliggenhetsadresse.landkode,registreringsdatoIEnhetsregisteret,frivilligMvaRegistrertBeskrivelser,registrertIMvaregisteret,oppstartsdato,datoEierskifte,nedleggelsesdato
811545082,SOUNDS LIKE NORWAY,999557244,BEDR,Underenhet til næringsdrivende og offentlig forvaltning,90.020,Tjenester tilknyttet underholdningsvirksomhet,,,,,,,true,,,,,,,,,,Ryes gate 12D,KONGSBERG,3616,KONGSBERG,3303,Norge,NO,2013-02-11,,false,2023-02-01,,
811545112,GAUSDAL LANDHANDLERI AS AVD JESSHEIM,933735842,BEDR,Underenhet til næringsdrivende og offentlig forvaltning,46.739,Engroshandel med byggevarer ikke nevnt annet sted,,,,,,,true,18,,,,,,,,,Henrik Bulls veg 104,JESSHEIM,2052,ULLENSAKER,3209,Norge,NO,2013-02-11,,false,2013-05-01,,
811545252,RAFFINERITOMTA EVJE AS,999666337,BEDR,Underenhet til næringsdrivende og offentlig forvaltning,68.209,Utleie av egen eller leid fast eiendom ellers,,,,,,,false,,,Isefjærveien 190,HØVÅG,4770,LILLESAND,4215,Norge,NO,Erdvig,HØVÅG,4770,LILLESAND,4215,Norge,NO,2013-02-11,,false,2013-01-29,,
811549932,B & Y TRANSPORT AS,925554243,BEDR,Underenhet til næringsdrivende og offentlig forvaltning,49.410,Godstransport på vei,,,,,,,true,10,,,,,,,,,Orionvegen 52,HVAM,2165,NES,3228,Norge,NO,2013-02-11,,false,2013-02-01,2020-09-11,
811550752,PJT AS,999657273,BEDR,Underenhet til næringsdrivende og offentlig forvaltning,49.410,Godstransport på vei,,,,,,,true,,,,,,,,,,v/Per Johannessen/nMyrdalskogen 11,ULSET,5118,BERGEN,4601,Norge,NO,2013-02-11,,false,2013-01-24,,
811552402,KIRKEPARTNER AS,911625504,BEDR,Underenhet til næringsdrivende og offentlig forvaltning,62.030,Forvaltning og drift av IT-systemer,,,,,,,true,27,www.kirkepartner.no,Postboks 535 Sentrum,OSLO,0105,OSLO,0301,Norge,NO,Fred. Olsens gate 1,OSLO,0152,OSLO,0301,Norge,NO,2013-02-11,,false,2013-01-29,2018-04-11,
811553212,HULDRA FILM AS,999553435,BEDR,Underenhet til næringsdrivende og offentlig forvaltning,59.110,"Produksjon av film, video og fjernsynsprogrammer",,,,,,,true,,,c/o Harald Omland/nFriisebrygga 4,PORSGRUNN,3921,PORSGRUNN,4001,Norge,NO,Friisebrygga 4,PORSGRUNN,3921,PORSGRUNN,4001,Norge,NO,2013-02-11,,false,2013-01-14,,
811553352,FÅDAL BYGG AS,999646956,BEDR,Underenhet til næringsdrivende og offentlig forvaltning,41.200,Oppføring av bygninger,,,,,,,true,5,fadalbygg.no,,,,,,,,Savalveien 159,TYNSET,2500,TYNSET,3427,Norge,NO,2013-02-11,,false,2013-01-08,,
811553662,NETS BRANCH NORWAY,996345734,BEDR,Underenhet til næringsdrivende og offentlig forvaltning,62.030,Forvaltning og drift av IT-systemer,,,,,,,true,292,www.nets.eu,,,,,,,,Haavard Martinsens vei 54,OSLO,0978,OSLO,0301,Norge,NO,2013-02-11,,false,2013-02-06,,
```

The `underenheter.csv->overordnetEnhet` is looked up in `enheter.csv->organisasjonsnummer`,
however there are some data inconsistencies.
I need to detect and remove any lines from `underenheter.csv` that fails to look `overordnetEnhet`
in `enheter.csv->organisasjonsnummer`.

Can you write me a succinct python program that does this for me?
"""
