import React from 'react'
import { Form, Header, Segment } from 'semantic-ui-react'

import { groupByToArray } from 'helpers/enumerableExtensions'
import getField from './getField'

const extendedEditors = [7, 8, 9] // Activities, Addresses, Persons
const isOdd = x => x / 2 !== 0
const IsLargeEditor = prop => extendedEditors.indexOf(prop.selector) !== -1

const Group = ({ value, errors, onChange, localize, localizeKey }) => {
  let offset = 0
  const keySelector = (v, i) => {
    const position = i + offset
    const isLarge = IsLargeEditor(v)
    if (isLarge && isOdd(position)) offset += 1
    const index = Math.floor((i + offset) / 2)
    if (isLarge) offset += 1
    return index
  }
  return (
    <Segment key={localizeKey}>
      <Header as="h4" content={localize(localizeKey)} dividing />
      {groupByToArray(value, keySelector)
        .map(({ value: items }) => (
          <Form.Group key={items[0].name} widths="equal">
            {items.map(v => getField(v, errors[v.name], onChange, localize))}
            {!IsLargeEditor(items[0]) && isOdd(items.length) &&
              <div className="field" />}
          </Form.Group>
        ))}
    </Segment>
  )
}

export default (fields, errors, onChange, localize) =>
  groupByToArray(fields, v => v.groupName)
    .map(({ key, value }) =>
      <Group {...{ key, value, errors, onChange, localize, localizeKey: key || 'Other' }} />)
