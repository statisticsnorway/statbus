import { parse as parseXml } from 'fast-xml-parser'
import { parse as parseCsv } from 'papaparse'
import { pipe, union, keys, values } from 'ramda'

function isObject(data) {
  return data != null && typeof data === 'object'
}
function hasNested(data) {
  return values(data).some(isObject)
}
function unionBy(asFn) {
  return function comapare(prev, curr) {
    return union(prev, asFn(curr))
  }
}

function getXmlAttributes(parsed) {
  return Array.isArray(parsed)
    ? parsed.reduce(unionBy(keys), [])
    : isObject(parsed)
      ? hasNested(parsed) ? values(parsed).reduce(unionBy(getXmlAttributes), []) : keys(parsed)
      : []
}

function getCsvAttributes(parsed) {
  const startFrom = parsed.data.findIndex(x => x.length > 1)
  return {
    attributes: parsed.data[startFrom],
    delimiter: parsed.meta.delimiter,
    startFrom,
  }
}

export const fromXml = pipe(parseXml, getXmlAttributes)
export const fromCsv = pipe(parseCsv, getCsvAttributes)
