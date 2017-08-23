import { groupByToArray } from 'helpers/enumerableExtensions'

// is one of Activities, Addresses or Persons
const isExtended = type => [7, 8, 9].includes(type)

const toGroupProps = ({ key, value }) => ({
  explicitKey: key,
  isExtended: isExtended(key),
  content: value,
})

// TODO: isExtended is not rendered as extended field
const toSection = ({ key, value }) => {
  let offset = 0
  const byOffset = ({ fieldType }, i) => {
    const isLarge = isExtended(fieldType)
    if (isLarge && (i + offset) % 2 !== 0) offset += 1
    const index = Math.floor((i + offset) / 2)
    if (isLarge) offset += 1
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
