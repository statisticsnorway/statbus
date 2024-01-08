import React from 'react'
import { shape, arrayOf, func, string, bool } from 'prop-types'
import { Icon, Table, Message } from 'semantic-ui-react'
import * as R from 'ramda'

import { getDate, formatDate } from '/helpers/dateHelper'
import ActivityView from './View.jsx'
import ActivityEdit from './Edit.jsx'

export class ActivitiesList extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    locale: string.isRequired,
    name: string.isRequired,
    value: arrayOf(shape({})),
    onChange: func,
    label: string,
    readOnly: bool,
    errors: arrayOf(string),
    disabled: bool,
    popuplocalizedKey: string,
  }

  static defaultProps = {
    value: [],
    readOnly: false,
    onChange: R.identity,
    label: '',
    errors: [],
    disabled: false,
    popuplocalizedKey: undefined,
  }

  state = {
    addRow: false,
    editRow: undefined,
    newRowId: -1,
  }

  editHandler = (index) => {
    this.setState({
      editRow: index,
    })
  }

  deleteHandler = (index) => {
    this.changeHandler(this.props.value.filter((v, itemIndex) => itemIndex !== index))
  }

  saveHandler = (value, itemIndex) => {
    this.changeHandler(this.props.value.map((v, index) => (index === itemIndex ? value : v)))
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
    const { name, onChange } = this.props
    onChange({ target: { name, value } }, { ...this.props, value })
  }

  renderRows() {
    const { readOnly, value, localize, disabled } = this.props
    const { addRow, editRow } = this.state
    const renderComponent = (x, index) =>
      index !== editRow ? (
        <ActivityView
          key={index}
          value={x}
          onEdit={this.editHandler}
          onDelete={this.deleteHandler}
          readOnly={readOnly}
          editMode={editRow !== undefined || addRow}
          localize={localize}
          index={index}
        />
      ) : (
        <ActivityEdit
          key={index}
          value={x}
          onSave={this.saveHandler}
          onCancel={this.editCancelHandler}
          localize={localize}
          disabled={disabled}
          index={index}
        />
      )
    return value
      .sort((a, b) => a.activityType - b.activityType)
      .map((el, index) => renderComponent(el, index))
  }

  render() {
    const {
      readOnly,
      value,
      label: labelKey,
      localize,
      errors,
      name,
      disabled,
      locale,
      required,
    } = this.props
    const { addRow, editRow, newRowId } = this.state
    const label = localize(labelKey)
    return (
      <div className="field">
        {!readOnly && (
          <label className={required ? 'is-required' : ''} htmlFor={name}>
            {label}
          </label>
        )}
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
                  {editRow === undefined && addRow === false && (
                    <div data-tooltip={localize('ButtonAdd')} data-position="top center">
                      <Icon
                        name="add"
                        onClick={disabled ? R.identity : this.addHandler}
                        disabled={disabled}
                        color="green"
                        size="big"
                      />
                    </div>
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
                  activityYear: 0,
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
                locale={locale}
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
