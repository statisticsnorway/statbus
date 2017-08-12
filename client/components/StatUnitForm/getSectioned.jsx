import React from 'react'
import { Form } from 'semantic-ui-react'

import { groupByToArray } from 'helpers/enumerableExtensions'

// [7, 8, 9] is [Activities, Addresses, Persons]
const isExtended = type => [7, 8, 9].includes(type)
const isOdd = x => x / 2 !== 0

const toGroup = (key, items) => (
  <Form.Group key={key}>
    {...items.map(item => item.component)}
    {!isExtended(key) && isOdd(items.length) &&
      <div className="field" />}
  </Form.Group>
)

const toSection = (key, items) => {
  let offset = 0
  const byOffset = (item, i) => {
    const isLarge = isExtended(item.type)
    if (isLarge && isOdd(i + offset)) offset += 1
    const index = Math.floor((i + offset) / 2)
    if (isLarge) offset += 1
    return index
  }
  return {
    key,
    value: groupByToArray(items, byOffset)
      .map(group => toGroup(group.key, group.value)),
  }
}

const bySection = item => item.section

export default fieldsWithMeta =>
  groupByToArray(fieldsWithMeta, bySection)
    .map(group => toSection(group.key, group.value))
