import { parse as parseXml } from 'fast-xml-parser'
import { parse as parseCsv } from 'papaparse'
import { pipe, union, keys } from 'ramda'

const polishParsedCsv = result => result.data

const getAttributes = data => Array.isArray(data)
  ? data.reduce((prev, curr) => union(prev, keys(curr)), [])
  : data && typeof (data) === 'object'
    ? Object.entries(data).reduce(
      (acc, [, value]) => [...acc, ...getAttributes(value)],
      [],
    )
    : []

export const parseXML = pipe(parseXml, getAttributes)
export const parseCSV = pipe(parseCsv, polishParsedCsv, getAttributes)
