ALTER TABLE tmp.underenhet ADD prn FLOAT DEFAULT random();
CREATE INDEX underenhet_prn_idx ON tmp.underenhet(prn);

SELECT "organisasjonsnummer" AS underenhet_orgnr
      ,"overordnetEnhet" AS enhet_orgnr
INTO TABLE tmp.selection
FROM tmp.underenhet
WHERE EXISTS(SELECT * FROM tmp.enhet WHERE enhet."organisasjonsnummer" = underenhet."overordnetEnhet")
ORDER BY prn
LIMIT 1000;

ALTER TABLE tmp.underenhet DROP prn;
