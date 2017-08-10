import React from 'react'
import PropTypes from 'prop-types'
import { Form, Segment, Header } from 'semantic-ui-react'

import { groupByToArray } from 'helpers/enumerableExtensions'

const extendedEditors = [7, 8, 9] // Activities, Addresses, Persons
const isOdd = x => x / 2 !== 0
const IsLargeEditor = prop => extendedEditors.indexOf(prop.selector) !== -1

const Group = ({ title, children }) => {
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
    <Section key={title} title={title}>
      {groupByToArray(value, keySelector)
        .map(({ value: items }) => (
          <Form.Group key={items[0].name} widths="equal">
            {!IsLargeEditor(items[0]) && isOdd(items.length) &&
              <div className="field" />}
          </Form.Group>
        ))}
    </Section>
  )
}

export default (fields, errors, onChange, localize) =>
  groupByToArray(fields, v => v.groupName)
    .map(({ key, value }) =>
      <Group {...{ key, value, errors, onChange, localize, localizeKey: key || 'Other' }} />)
