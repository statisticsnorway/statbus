ALTER TABLE tmp.underenhet ADD periodic_random FLOAT DEFAULT random();
CREATE INDEX underenhet_periodic_random_idx ON tmp.underenhet(periodic_random);

SELECT "organisasjonsnummer" AS underenhet_orgnr
      ,"overordnetEnhet" AS enhet_orgnr
      , periodic_random
INTO TABLE tmp.selection
FROM tmp.underenhet
WHERE EXISTS(SELECT * FROM tmp.enhet WHERE enhet."organisasjonsnummer" = underenhet."overordnetEnhet")
ORDER BY periodic_random;

ALTER TABLE tmp.underenhet DROP periodic_random;
