import React from 'react'
import PropTypes from 'prop-types'
import { Checkbox, Table, List, Label } from 'semantic-ui-react'

import ListWithDnd from 'components/ListWithDnd'
import { predicateFields } from 'helpers/enums'

const listStyle = { display: 'inline-block' }
const fields = [...predicateFields]

const FieldsEditor = ({ value: selected, onChange, localize }) => {
  const onAdd = (_, { id }) => onChange([...selected, id])
  const onRemove = (_, { id }) => onChange(selected.filter(y => y !== id))
  const allItems = fields.map(([key, text]) => {
    const checked = selected.includes(key)
    const props = { id: key, checked, label: localize(text), onClick: checked ? onRemove : onAdd }
    return { key, content: <Checkbox {...props} /> }
  })
  return (
    <Table basic="very" celled>
      <Table.Header>
        <Table.Row>
          <Table.HeaderCell content={localize('FieldsToSelect')} width={8} textAlign="center" />
          <Table.HeaderCell content={localize('SelectedFields')} width={8} textAlign="center" />
        </Table.Row>
      </Table.Header>
      <Table.Body>
        <Table.Row verticalAlign="top">
          <Table.Cell textAlign="center" width={8}>
            <List items={allItems} className="left aligned" style={listStyle} />
          </Table.Cell>
          <Table.Cell textAlign="center" width={8}>
            <ListWithDnd
              value={selected}
              onChange={onChange}
              renderItem={key => (
                <Label
                  id={key}
                  content={localize(predicateFields.get(key))}
                  onRemove={onRemove}
                  size="large"
                />
              )}
            />
          </Table.Cell>
        </Table.Row>
      </Table.Body>
    </Table>
  )
}

const { arrayOf, func, number } = PropTypes
FieldsEditor.propTypes = {
  value: arrayOf(number).isRequired,
  onChange: func.isRequired,
  localize: func.isRequired,
}

export default FieldsEditor
