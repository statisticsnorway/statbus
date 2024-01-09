import React from 'react'
import { Table, Checkbox } from 'semantic-ui-react'
import systemFunctions from '/helpers/systemFunctions'

const FunctionalAttributes = ({ localize, value, onChange, label, name }) => {
  const onChangeCreator = propName => (e, { checked }) => {
    onChange({ name, value: systemFunctions.get(propName), checked })
  }

  const isChecked = fname => value.some(x => x === systemFunctions.get(fname))

  const renderTableRow = (attribute, read, create, update, del) => (
    <Table.Row key={attribute}>
      <Table.Cell>{localize(attribute)}</Table.Cell>
      <Table.Cell>
        <Checkbox
          name="hidden"
          onChange={onChangeCreator(`${attribute}View`)}
          checked={isChecked(`${attribute}View`)}
        />
      </Table.Cell>
      <Table.Cell>
        {create && (
          <Checkbox
            name="hidden"
            onChange={onChangeCreator(`${attribute}Create`)}
            checked={isChecked(`${attribute}Create`)}
          />
        )}
      </Table.Cell>
      <Table.Cell>
        <Checkbox
          name="hidden"
          onChange={onChangeCreator(`${attribute}Edit`)}
          checked={isChecked(`${attribute}Edit`)}
        />
      </Table.Cell>
      <Table.Cell>
        {del && (
          <Checkbox
            name="hidden"
            onChange={onChangeCreator(`${attribute}Delete`)}
            checked={isChecked(`${attribute}Delete`)}
          />
        )}
      </Table.Cell>
    </Table.Row>
  )

  return (
    <div className="field">
      <label htmlFor={name}>{label}</label>
      <Table id={name} definition>
        <Table.Header>
          <Table.Row>
            <Table.HeaderCell />
            <Table.HeaderCell>{localize('Read')}</Table.HeaderCell>
            <Table.HeaderCell>{localize('Create')}</Table.HeaderCell>
            <Table.HeaderCell>{localize('Update')}</Table.HeaderCell>
            <Table.HeaderCell>{localize('Delete')}</Table.HeaderCell>
          </Table.Row>
        </Table.Header>
        <Table.Body>
          {renderTableRow('Account', true, false, true, false)}
          {renderTableRow('Roles', true, true, true, true)}
          {renderTableRow('Users', true, true, true, true)}
          {renderTableRow('StatUnits', true, true, true, true)}
          {renderTableRow('Regions', true, true, true, true)}
          {renderTableRow('Address', true, true, true, true)}
          {renderTableRow('LinkUnits', true, true, false, true)}
          {renderTableRow('DataSourceQueues', true, false, false, false)}
        </Table.Body>
      </Table>
    </div>
  )
}

export default FunctionalAttributes
