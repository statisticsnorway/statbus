import React from 'react'
import { Table, Checkbox } from 'semantic-ui-react'
import { wrapper } from 'helpers/locale'
import systemFunctions from 'helpers/systemFunctions'

const FunctionalAttributes = ({ localize, value, onChange, label, name }) => {
  const onChangeCreator = (propName) => (e, { checked }) => {
    onChange({ name, value: systemFunctions.get(propName), checked })
  }
  const isChecked = name => value.some(x => x === systemFunctions.get(name))
  return (
    <div className="field">
      <label>{label}</label>
      <Table definition>
        <Table.Header>
          <Table.Row>
            <Table.HeaderCell />
            <Table.HeaderCell>{localize('Create')}</Table.HeaderCell>
            <Table.HeaderCell>{localize('Read')}</Table.HeaderCell>
            <Table.HeaderCell>{localize('Update')}</Table.HeaderCell>
            <Table.HeaderCell>{localize('Delete')}</Table.HeaderCell>
          </Table.Row>
        </Table.Header>
        <Table.Body>
          <Table.Row>
            <Table.Cell>{localize('Account')}</Table.Cell>
            <Table.Cell></Table.Cell>
            <Table.Cell>
              <Checkbox name="hidden" onChange={onChangeCreator('AccountView')} checked={isChecked('AccountView')} />
            </Table.Cell>
            <Table.Cell>
              <Checkbox name="hidden" onChange={onChangeCreator('AccountEdit')} checked={isChecked('AccountEdit')} />
            </Table.Cell>
            <Table.Cell></Table.Cell>
          </Table.Row>
          <Table.Row>
            <Table.Cell>{localize('Roles')}</Table.Cell>
            <Table.Cell>
              <Checkbox name="hidden" onChange={onChangeCreator('RoleView')} checked={isChecked('RoleView')} />
            </Table.Cell>
            <Table.Cell>
              <Checkbox name="hidden" onChange={onChangeCreator('RoleCreate')} checked={isChecked('RoleCreate')} />
            </Table.Cell>
            <Table.Cell>
              <Checkbox name="hidden" onChange={onChangeCreator('RoleEdit')} checked={isChecked('RoleEdit')} />
            </Table.Cell>
            <Table.Cell>
              <Checkbox name="hidden" onChange={onChangeCreator('RoleDelete')} checked={isChecked('RoleDelete')} />
            </Table.Cell>
          </Table.Row>
          <Table.Row>
            <Table.Cell>{localize('Users')}</Table.Cell>
            <Table.Cell>
              <Checkbox name="hidden" onChange={onChangeCreator('UserView')} checked={isChecked('UserView')} />
            </Table.Cell>
            <Table.Cell>
              <Checkbox name="hidden" onChange={onChangeCreator('UserCreate')} checked={isChecked('UserCreate')} />
            </Table.Cell>
            <Table.Cell>
              <Checkbox name="hidden" onChange={onChangeCreator('UserEdit')} checked={isChecked('UserEdit')} />
            </Table.Cell>
            <Table.Cell>
              <Checkbox name="hidden" onChange={onChangeCreator('UserDelete')} checked={isChecked('UserDelete')} />
            </Table.Cell>
          </Table.Row>
          <Table.Row>
            <Table.Cell>{localize('StatUnits')}</Table.Cell>
            <Table.Cell>
              <Checkbox name="hidden" onChange={onChangeCreator('StatUnitView')} checked={isChecked('StatUnitView')} />
            </Table.Cell>
            <Table.Cell>
              <Checkbox name="hidden" onChange={onChangeCreator('StatUnitCreate')} checked={isChecked('StatUnitCreate')} />
            </Table.Cell>
            <Table.Cell>
              <Checkbox name="hidden" onChange={onChangeCreator('StatUnitEdit')} checked={isChecked('StatUnitEdit')} />
            </Table.Cell>
            <Table.Cell>
              <Checkbox name="hidden" onChange={onChangeCreator('StatUnitDelete')} checked={isChecked('StatUnitDelete')} />
            </Table.Cell>
          </Table.Row>
        </Table.Body>
      </Table>
    </div>
  )
}

export default wrapper(FunctionalAttributes)
