import React from 'react'
import { Form, Header, Segment } from 'semantic-ui-react'

import { groupByToArray } from 'helpers/enumerableExtensions'
import getField from './getField'

const modulo = 2

const extendedEditors = [7, 8, 9] // Activities and Addresses and Persons

const IsLargeEditor = property => extendedEditors.indexOf(property.selector) !== -1

const GroupFields = ({ value, errors, onChange, localize, localizeKey }) => {
  let offset = 0
  const keySelector = (v, ix) => {
    const position = ix + offset
    const isLarge = IsLargeEditor(v)
    if (isLarge && position % modulo !== 0) offset += 1
    const index = Math.floor((ix + offset) / modulo)
    if (isLarge) offset += 1
    return index
  }
  const groups = groupByToArray(value, keySelector)
  const sureKey = localizeKey || 'Other'
  return (
    <Segment key={`Form${localizeKey}`}>
      <Header as="h4" content={localize(sureKey)} dividing />
      {groups.map(({ value: items }, ix) => (
        <Form.Group widths="equal" key={`Group${sureKey}${ix}`}>
          {items.map(v => getField(v, errors[v.name], onChange, localize))}
          {!IsLargeEditor(items[0])
            && items.length % modulo !== 0
            && <div className="field" key={`Group${sureKey}Fake`} />}
        </Form.Group>
      ))}
    </Segment>
  )
}

export default (fields, errors, onChange, localize) =>
  groupByToArray(fields, v => v.groupName)
    .map(({ key, value }) =>
      <GroupFields {...{ key, value, errors, onChange, localize, localizeKey: key }} />)
