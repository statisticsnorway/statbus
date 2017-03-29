import React from 'react'
import { Button, Table, Form } from 'semantic-ui-react'

import DatePicker from 'components/fields/DateField'
import { wrapper } from 'helpers/locale'
import activityTypes from './activityTypes'

const activities = [...activityTypes.entries()].map(([key, value]) => ({ key, value }))
const years = Array.from(new Array(new Date().getFullYear() - 1899), (x, i) => {
  const year = new Date().getFullYear() - i
  return { value: year, text: year }
})

const { shape, number, func, string } = React.PropTypes

class ActivityEdit extends React.Component {
  static propTypes = {
    data: shape({
      id: number,
      activityRevx: number,
      activityRevy: number,
      activityYear: number,
      activityType: number,
      employees: number,
      turnover: number,
      activityRevxCategory: shape({
        code: string.isRequired,
        name: string.isRequired,
      }),
    }).isRequired,
    onSave: func.isRequired,
    onCancel: func.isRequired,
    localize: func.isRequired,
  }

  state = {
    ...this.props.data,
  }

  onFieldChange = (e, { name, value }) => {
    this.setState({
      [name]: value,
    })
  }

  saveHandler = () => {
    const { onSave } = this.props
    onSave(this.state)
  }

  cancelHandler = () => {
    const { onCancel } = this.props
    onCancel(this.state.id)
  }

  render() {
    const data = this.state
    const { localize } = this.props
    return (
      <Table.Row>
        <Table.Cell colSpan={8}>
          <Form as="div">
            <Form.Group widths="equal">
              <Form.Input
                label={localize('StatUnitActivityRevX')}
                name="activityRevxCode"
                value={data.activityRevxCategory.code}
              />
              <Form.Input
                label={localize('Activity')}
                value={data.activityRevxCategory.name}
                readOnly
              />
            </Form.Group>
            <Form.Group widths="equal">
              <Form.Select
                label={localize('StatUnitActivityType')}
                options={activities.map(({ key, value }) => ({ value: key, text: localize(value) }))}
                value={data.activityType}
                name="activityType"
                onChange={this.onFieldChange}
              />
              <Form.Input
                label={localize('StatUnitActivityEmployeesNumber')}
                type="number"
                name="employees"
                value={data.employees}
                onChange={this.onFieldChange}
              />
            </Form.Group>
            <Form.Group widths="equal">
              <Form.Select
                label={localize('TurnoverYear')}
                options={years}
                value={data.activityYear}
                name="activityYear"
                onChange={this.onFieldChange}
                search
              />
              <Form.Input
                label={localize('Turnover')}
                name="turnover"
                type="number"
                value={data.turnover}
                onChange={this.onFieldChange}
              />
            </Form.Group>
            <Form.Group widths="equal">
              <DatePicker
                labelKey="StatUnitActivityDate"
                type="number"
                name="idDate"
                value={data.idDate}
                onChange={this.onFieldChange}
              />
              <div className="field right aligned">
                <label>&nbsp;</label>
                <Button.Group>
                  <Button icon="check" color="green" onClick={this.saveHandler} />
                  <Button icon="cancel" color="red" onClick={this.cancelHandler} />
                </Button.Group>
              </div>
            </Form.Group>
          </Form>
        </Table.Cell>
      </Table.Row>
    )
  }
}

export default wrapper(ActivityEdit)

