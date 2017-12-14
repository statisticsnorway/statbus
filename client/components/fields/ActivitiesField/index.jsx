import React from 'react'
import { shape, arrayOf, func, string, bool } from 'prop-types'
import { Icon, Table, Popup, Message } from 'semantic-ui-react'

import { getDate, formatDate } from 'helpers/dateHelper'
import ActivityView from './View'
import ActivityEdit from './Edit'

const stubF = _ => _

class ActivitiesList extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    name: string.isRequired,
    value: arrayOf(shape({})),
    setFieldValue: func,
    label: string,
    readOnly: bool,
    errors: arrayOf(string),
    disabled: bool,
  }

  static defaultProps = {
    value: [],
    readOnly: false,
    setFieldValue: v => v,
    label: '',
    errors: [],
    disabled: false,
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
    this.changeHandler(this.props.value.filter(v => v.id !== id))
  }

  saveHandler = (value) => {
    this.changeHandler(this.props.value.map(v => (v.id === value.id ? value : v)))
    this.setState({ editRow: undefined })
  }

  editCancelHandler = () => {
    this.setState({ editRow: undefined })
  }

  addHandler = () => {
    this.setState({ addRow: true })
  }

  addSaveHandler = (value) => {
    this.changeHandler([value, ...this.props.value])
    this.setState(s => ({
      addRow: false,
      newRowId: s.newRowId - 1,
    }))
  }

  addCancelHandler = () => {
    this.setState({ addRow: false })
  }

  changeHandler(value) {
    this.props.setFieldValue(this.props.name, value)
  }

  renderRows() {
    const { readOnly, value, localize, disabled } = this.props
    const { addRow, editRow } = this.state
    return value
      .sort((a, b) => a.activityType - b.activityType)
      .map(v =>
        v.id !== editRow ? (
          <ActivityView
            key={v.id}
            value={v}
            onEdit={this.editHandler}
            onDelete={this.deleteHandler}
            readOnly={readOnly}
            editMode={editRow !== undefined || addRow}
            localize={localize}
          />
        ) : (
          <ActivityEdit
            key={v.id}
            value={v}
            onSave={this.saveHandler}
            onCancel={this.editCancelHandler}
            localize={localize}
            disabled={disabled}
          />
        ))
  }

  render() {
    const { readOnly, value, label: labelKey, localize, errors, name, disabled } = this.props
    const { addRow, editRow, newRowId } = this.state
    const label = localize(labelKey)
    return (
      <div className="field">
        {!readOnly && <label className="is-required" htmlFor={name}>{label}</label>}
        <Table size="small" id={name} compact celled>
          <Table.Header>
            <Table.Row>
              <Table.HeaderCell width={1} content={localize('StatUnitActivityRevXShort')} />
              <Table.HeaderCell width={5 + readOnly} content={localize('Activity')} />
              <Table.HeaderCell
                width={2}
                textAlign="center"
                content={localize('StatUnitActivityType')}
              />
              <Table.HeaderCell
                width={2}
                textAlign="center"
                content={localize('StatUnitActivityEmployeesNumber')}
              />
              <Table.HeaderCell width={2} textAlign="center" content={localize('Turnover')} />
              <Table.HeaderCell width={1} textAlign="center" content={localize('Year')} />
              {!readOnly && (
                <Table.HeaderCell width={1} textAlign="right">
                  {editRow === undefined &&
                    addRow === false && (
                      <Popup
                        trigger={
                          <Icon
                            name="add"
                            onClick={disabled ? stubF : this.addHandler}
                            disabled={disabled}
                            color="green"
                            size="big"
                          />
                        }
                        content={localize('ButtonAdd')}
                        size="mini"
                      />
                    )}
                </Table.HeaderCell>
              )}
            </Table.Row>
          </Table.Header>
          <Table.Body>
            {addRow && (
              <ActivityEdit
                value={{
                  id: newRowId,
                  activityYear: new Date().getFullYear(),
                  activityType: 1,
                  employees: '',
                  turnover: '',
                  idDate: formatDate(getDate()),
                  activityCategoryId: undefined,
                }}
                onSave={this.addSaveHandler}
                onCancel={this.addCancelHandler}
                localize={localize}
                disabled={disabled}
              />
            )}
            {value.length === 0 && !addRow ? (
              <Table.Row>
                <Table.Cell textAlign="center" colSpan="7" content={localize('TableNoRecords')} />
              </Table.Row>
            ) : (
              this.renderRows()
            )}
          </Table.Body>
        </Table>
        {errors.length !== 0 && <Message error title={label} list={errors.map(localize)} />}
      </div>
    )
  }
}

export default ActivitiesList
