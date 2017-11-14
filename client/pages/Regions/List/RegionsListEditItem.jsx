import React from 'react'
import { func, shape, number, string, bool } from 'prop-types'
import { Button, Input, Table } from 'semantic-ui-react'

class RegionsListEditItem extends React.Component {
  static propTypes = {
    data: shape({
      id: number.isRequired,
      code: string.isRequired,
      name: string.isRequired,
      adminstrativeCenter: string,
      isDeleted: bool,
    }).isRequired,
    onSave: func.isRequired,
    onCancel: func.isRequired,
  }
  state = {
    name: this.props.data.name,
    code: this.props.data.code,
    adminstrativeCenter: this.props.data.adminstrativeCenter,
    isDeleted: this.props.data.isDeleted || false,
  }
  handleSave = () => {
    const { onSave, data } = this.props
    onSave(data.id, { ...this.state })
  }
  handleCancel = () => {
    this.props.onCancel()
  }
  handleFieldChange = (e, { name, value }) => {
    this.setState({
      [name]: value,
    })
  }

  render() {
    const { name, code, adminstrativeCenter } = this.state
    return (
      <Table.Row>
        <Table.Cell>
          <Input name="code" value={code} onChange={this.handleFieldChange} size="small" fluid />
        </Table.Cell>
        <Table.Cell>
          <Input value={name} name="name" onChange={this.handleFieldChange} size="small" fluid />
        </Table.Cell>
        <Table.Cell>
          <Input
            name="adminstrativeCenter"
            value={adminstrativeCenter}
            onChange={this.handleFieldChange}
            size="small"
            fluid
          />
        </Table.Cell>

        <Table.Cell width={2} textAlign="right">
          <Button.Group size="mini">
            <Button icon="check" color="green" onClick={this.handleSave} />
            <Button icon="cancel" color="red" onClick={this.handleCancel} />
          </Button.Group>
        </Table.Cell>
      </Table.Row>
    )
  }
}

export default RegionsListEditItem
