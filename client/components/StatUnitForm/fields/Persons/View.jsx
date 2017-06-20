import React from 'react'
import { Icon, Table, Popup, Confirm } from 'semantic-ui-react'

import { getDate, formatDate } from 'helpers/dateHelper'
import personTypes from 'helpers/personTypes'

const { shape, string, number, func, bool, oneOfType, arrayOf } = React.PropTypes

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
    }).isRequired,
    onEdit: func.isRequired,
    onDelete: func.isRequired,
    readOnly: bool.isRequired,
    editMode: bool.isRequired,
    localize: func.isRequired,
    countries: arrayOf(shape({})),
  }

  static defaultProps = {
    data: {
      id: -1,
      givenName: '',
      personalId: '',
      surname: '',
      birthDate: formatDate(getDate()),
      sex: '',
      role: '',
      countryId: '',
      phoneNumber: '',
      phoneNumber1: '',
      address: '',
    },
    countries: [],
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
    this.setState({ showConfirm: false })
    const { data, onDelete } = this.props
    onDelete(data.id)
  }

  render() {
    const { data, readOnly, editMode, localize, countries } = this.props
    const { showConfirm } = this.state
    const country = countries.find(c => c.value === data.countryId)
    return (
      <Table.Row>
        <Table.Cell>{`${data.givenName} ${data.surname}`}</Table.Cell>
        <Table.Cell>{data.personalId}</Table.Cell>
        <Table.Cell textAlign="center">{localize(personTypes.get(data.role))}</Table.Cell>
        <Table.Cell textAlign="center">{country && country.text}</Table.Cell>
        <Table.Cell textAlign="center">{data.phoneNumber}</Table.Cell>
        <Table.Cell textAlign="center">{data.address}</Table.Cell>
        {!readOnly &&
          <Table.Cell singleLine textAlign="right">
            {!editMode &&
              <span>
                <Popup
                  trigger={<Icon name="edit" color="blue" onClick={this.editHandler} />}
                  content={localize('EditButton')}
                  size="mini"
                />
                <Popup
                  trigger={<Icon name="trash" color="red" onClick={this.deleteHandler} />}
                  content={localize('ButtonDelete')}
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
            }
          </Table.Cell>
        }
      </Table.Row>
    )
  }
}

export default PersonView
