import React from 'react'
import { Form, Header, Segment } from 'semantic-ui-react'

import { groupByToArray } from 'helpers/enumerableExtensions'
import getField from 'components/getField'


const GroupFields = (key, items, errors, onChange, localize) => {
  const modulo = key ? 2 : 1
  const localizeKey = key || 'Other'
  const groups = groupByToArray(items, (v, ix) => Math.floor(ix / modulo))
  return (
    <Segment key={`Form${localizeKey}`}>
      <Header as="h4" dividing>{localize(localizeKey)}</Header>
      {groups.map(({ value }, ix) =>
        <Form.Group widths="equal" key={`Group${localizeKey}${ix}`}>
          {value.map(v => getField(v, errors[v.name], onChange))}
          {value.length % modulo !== 0 && <div className="field" key={`Group${localizeKey}Fake`} />}
        </Form.Group>,
      )}
    </Segment>
  )
}

export default (fields, errors, onChange, localize) => groupByToArray(fields, v => v.groupName)
  .map(item => GroupFields(item.key, item.value, errors, onChange, localize))
