import React from 'react'
import { Form, Header, Segment } from 'semantic-ui-react'

import { groupByToArray } from 'helpers/enumerableExtensions'
import getField from 'components/getField'

const modulo = 2

const hugeEditors = [7, 8] // Activities and Addresses

const IsLargeEditor = property => hugeEditors.indexOf(property.selector) !== -1

const GroupFields = (key, items, errors, onChange, localize) => {
  let offset = 0
  const localizeKey = key || 'Other'
  const groups = groupByToArray(items, (v, ix) => {
    const position = ix + offset
    const isLargeEditor = IsLargeEditor(v)
    if (isLargeEditor && position % modulo !== 0) offset += 1
    const index = Math.floor((ix + offset) / modulo)
    if (isLargeEditor) offset += 1
    return index
  })
  return (
    <Segment key={`Form${localizeKey}`}>
      <Header as="h4" dividing>{localize(localizeKey)}</Header>
      {groups.map(({ value }, ix) =>
        <Form.Group widths="equal" key={`Group${localizeKey}${ix}`}>
          {value.map(v => getField(v, errors[v.name], onChange))}
          {!IsLargeEditor(value[0]) && value.length % modulo !== 0 && <div className="field" key={`Group${localizeKey}Fake`} />}
        </Form.Group>,
      )}
    </Segment>
  )
}

export default (fields, errors, onChange, localize) => groupByToArray(fields, v => v.groupName)
  .map(item => GroupFields(item.key, item.value, errors, onChange, localize))
