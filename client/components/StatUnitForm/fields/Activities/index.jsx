import React from 'react'
import { Icon, Table, Popup, Message } from 'semantic-ui-react'

import { getDate, formatDate } from 'helpers/dateHelper'
import ActivityView from './View'
import ActivityEdit from './Edit'

const { shape, arrayOf, func, string, bool } = React.PropTypes

class ActivitiesList extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    name: string.isRequired,
    data: arrayOf(shape({})),
    onChange: func,
    labelKey: string,
    readOnly: bool,
    errors: arrayOf(string).isRequired,
  }

  static defaultProps = {
    data: [],
    readOnly: false,
    onChange: v => v,
    labelKey: '',
  }

  state = {
    addRow: false,
    editRow: undefined,
    newRowId: -1,
  }

  editHandler = (id) => {
    this.setState({
      editRow: id,
    })
  }

  deleteHandler = (id) => {
    this.changeHandler(this.props.data.filter(v => v.id !== id))
  }

  saveHandler = (data) => {
    this.changeHandler(this.props.data.map(v => v.id === data.id ? data : v))
    this.setState({ editRow: undefined })
  }

  editCancelHandler = () => {
    this.setState({ editRow: undefined })
  }

  addHandler = () => {
    this.setState({ addRow: true })
  }

  addSaveHandler = (data) => {
    this.changeHandler([data, ...this.props.data])
    this.setState(s => ({
      addRow: false,
      newRowId: s.newRowId - 1,
    }))
  }

  addCancelHandler = () => {
    this.setState({ addRow: false })
  }

  changeHandler(value) {
    const { onChange, name } = this.props
    onChange({ name, value })
  }

  renderRows() {
    const { readOnly, data, localize } = this.props
    const { addRow, editRow } = this.state
    return (
      data.map(v => (
        v.id !== editRow
          ? (
            <ActivityView
              key={v.id}
              data={v}
              onEdit={this.editHandler}
              onDelete={this.deleteHandler}
              readOnly={readOnly}
              editMode={editRow !== undefined || addRow}
              localize={localize}
            />
          )
          : (
            <ActivityEdit
              key={v.id}
              data={v}
              onSave={this.saveHandler}
              onCancel={this.editCancelHandler}
              localize={localize}
            />
          )
      ))
    )
  }

  render() {
    const { readOnly, data, labelKey, localize, errors } = this.props
    const { addRow, editRow, newRowId } = this.state
    const label = localize(labelKey)
    return (
      <div className="field">
        {!readOnly && <label>{label}</label>}
        <Table size="small" compact celled>
          <Table.Header>
            <Table.Row>
              <Table.HeaderCell width={1}>{localize('StatUnitActivityRevXShort')}</Table.HeaderCell>
              <Table.HeaderCell width={5 + readOnly}>{localize('Activity')}</Table.HeaderCell>
              <Table.HeaderCell width={2} textAlign="center">{localize('StatUnitActivityType')}</Table.HeaderCell>
              <Table.HeaderCell width={2} textAlign="center">{localize('StatUnitActivityEmployeesNumber')}</Table.HeaderCell>
              <Table.HeaderCell width={2} textAlign="center">{localize('Turnover')}</Table.HeaderCell>
              <Table.HeaderCell width={1} textAlign="center">{localize('Year')}</Table.HeaderCell>
              <Table.HeaderCell width={2} textAlign="center">{localize('RegistrationDate')}</Table.HeaderCell>
              {!readOnly &&
                <Table.HeaderCell width={1} textAlign="right">
                  {editRow === undefined && addRow === false &&
                    <Popup
                      trigger={<Icon name="add" color="green" onClick={this.addHandler} />}
                      content={localize('ButtonAdd')}
                      size="mini"
                    />
                  }
                </Table.HeaderCell>
              }
            </Table.Row>
          </Table.Header>
          <Table.Body>
            {addRow &&
              <ActivityEdit
                data={{
                  id: newRowId,
                  activityRevy: 0,
                  activityYear: new Date().getFullYear(),
                  activityType: 1,
                  employees: '',
                  turnover: '',
                  idDate: formatDate(getDate()),
                  activityRevxCategory: {
                    code: '',
                    name: '',
                  },
                }}
                onSave={this.addSaveHandler}
                onCancel={this.addCancelHandler}
                localize={localize}
              />
            }
            {data.length === 0 && !addRow
              ? (
                <Table.Row>
                  <Table.Cell textAlign="center" colSpan="7">{localize('TableNoRecords')}</Table.Cell>
                </Table.Row>
              )
              : this.renderRows()
            }
          </Table.Body>
        </Table>
        {errors.length !== 0 && <Message error title={label} list={errors.map(localize)} />}
      </div>
    )
  }
}

export default ActivitiesList
