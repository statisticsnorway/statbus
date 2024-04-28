import React from 'react'
import { shape, string, number, func, bool, oneOfType, arrayOf } from 'prop-types'
import { Icon, Table, Popup, Confirm } from 'semantic-ui-react'

import { getDate, formatDate } from '/helpers/dateHelper'
import { personSex } from '/helpers/enums'
import { hasValue } from '/helpers/validation'
import { getNewName } from '/helpers/locale'

class PersonView extends React.Component {
  static propTypes = {
    data: shape({
      id: number,
      givenName: string.isRequired,
      personalId: oneOfType([string, number]),
      surname: string.isRequired,
      birthDate: string,
      sex: oneOfType([string, number]),
      role: oneOfType([string, number]),
      countryId: oneOfType([string, number]),
      phoneNumber: oneOfType([string, number]),
      phoneNumber1: oneOfType([string, number]),
      address: oneOfType([string, number]),
    }),
    onEdit: func.isRequired,
    onDelete: func.isRequired,
    readOnly: bool.isRequired,
    editMode: bool.isRequired,
    localize: func.isRequired,
    countries: arrayOf(shape({})),
    roles: arrayOf(shape({})),
  }

  static defaultProps = {
    data: {
      id: -1,
      givenName: '',
      personalId: '',
      surname: '',
      middleName: '',
      birthDate: formatDate(getDate()),
      sex: '',
      role: '',
      countryId: '',
      phoneNumber: '',
      phoneNumber1: '',
      address: '',
    },
    countries: [],
    roles: [],
  }

  state = {
    showConfirm: false,
  }

  editHandler = () => {
    const { data, onEdit } = this.props
    onEdit(data.id)
  }

  deleteHandler = () => {
    this.setState({ showConfirm: true })
  }

  cancelHandler = () => {
    this.setState({ showConfirm: false })
  }

  confirmHandler = () => {
    const {
      data: { id },
      onDelete,
    } = this.props
    this.setState({ showConfirm: false }, () => onDelete(id))
  }

  render() {
    const { data, readOnly, editMode, localize, countries, roles } = this.props
    const { showConfirm } = this.state
    const country = countries.find(c => c.value === data.countryId)
    const role = roles.find(x => x.id === data.role)
    return (
      <Table.Row>
        <Table.Cell content={data.personalId} />
        <Table.Cell
          content={`${hasValue(data.givenName) ? data.givenName : ''} ${
            hasValue(data.middleName) ? data.middleName : ''
          } ${hasValue(data.surname) ? data.surname : ''}`}
        />
        <Table.Cell content={localize(personSex.get(data.sex))} textAlign="center" />
        <Table.Cell content={country && getNewName(country, false)} textAlign="center" />
        <Table.Cell content={role && getNewName(role, false)} textAlign="center" />
        <Table.Cell content={data.phoneNumber} textAlign="center" />
        <Table.Cell content={data.phoneNumber1} textAlign="center" />
        {!readOnly && (
          <Table.Cell singleLine textAlign="right">
            {!editMode && (
              <span>
                <Popup
                  trigger={<Icon name="edit" color="blue" onClick={this.editHandler} />}
                  content={localize('EditButton')}
                  position="top center"
                  size="mini"
                />
                <Popup
                  trigger={<Icon name="trash" color="red" onClick={this.deleteHandler} />}
                  content={localize('ButtonDelete')}
                  position="top center"
                  size="mini"
                />
                <Confirm
                  open={showConfirm}
                  cancelButton={localize('No')}
                  confirmButton={localize('Yes')}
                  header={localize('DialogTitleDelete')}
                  content={localize('DialogBodyDelete')}
                  onCancel={this.cancelHandler}
                  onConfirm={this.confirmHandler}
                />
              </span>
            )}
          </Table.Cell>
        )}
      </Table.Row>
    )
  }
}

export default PersonView
