import { groupByToArray } from '/helpers/enumerable'

// is one of Activities, Addresses or Persons
const isExtended = type => [7, 8, 9].includes(type)

const toGroupProps = ({ key, value }) => ({
  key,
  isExtended: isExtended(value[0].fieldType),
  fieldsMeta: value,
})

const getSectionsArray = (arr) => {
  let offset = 0
  const len = arr.length
  let inSequenceFlag = false
  let lastIndex = 0
  return arr.reduce((acc, cur, i) => {
    const extended = isExtended(cur.fieldType)
    if (extended && (i + offset) % 2 !== 0) offset += 1
    const index = Math.floor((i + offset) / 2)

    if (i < len - 2 && arr[i + 2].order - arr[i + 1].order === 1 && !inSequenceFlag) {
      offset += 1
      inSequenceFlag = true
      return [...acc, index]
    }

    if (extended) offset += 1

    if (!inSequenceFlag) {
      lastIndex = index + 1
    }

    if (i < len - 1 && arr[i + 1].order - arr[i].order !== 1 && inSequenceFlag) {
      inSequenceFlag = false
      return [...acc, lastIndex++]
    }

    return [...acc, inSequenceFlag ? lastIndex : index]
  }, [])
}

const toSection = ({ key, value }) => {
  const indexes = getSectionsArray(value.map(x => x.props))
  const groups = groupByToArray(
    value.map(x => x.props),
    (_, i) => indexes[i],
  ).map(toGroupProps)

  return {
    key,
    groups,
  }
}

export default fieldsMeta => groupByToArray(fieldsMeta, x => x.section).map(toSection)
