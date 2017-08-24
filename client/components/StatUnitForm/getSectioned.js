import { groupByToArray } from 'helpers/enumerableExtensions'

// is one of Activities, Addresses or Persons
const isExtended = type => [7, 8, 9].includes(type)

const toGroupProps = ({ key, value }) => ({
  explicitKey: key,
  isExtended: isExtended(value[0].fieldType),
  content: value,
})

const toSection = ({ key, value }) => {
  let offset = 0
  const byOffset = ({ fieldType }, i) => {
    const extended = isExtended(fieldType)
    if (extended && (i + offset) % 2 !== 0) offset += 1
    const index = Math.floor((i + offset) / 2)
    if (extended) offset += 1
    return index
  }
  return {
    key,
    value: groupByToArray(value.map(x => x.props), byOffset)
      .map(toGroupProps),
  }
}

export default fieldsWithMeta =>
  groupByToArray(fieldsWithMeta, x => x.section)
    .map(toSection)
