import React from 'react'
import { Button, Input, Table } from 'semantic-ui-react'

const { func, shape, number, string, bool } = React.PropTypes

class RegionsListEditItem extends React.Component {
  static propTypes = {
    data: shape({
      id: number.isRequired,
      isDeleted: bool,
      name: string.isRequired,
    }).isRequired,
    onSave: func.isRequired,
    onCancel: func.isRequired,
  }
  state = {
    name: this.props.data.name,
    isDeleted: this.props.data.isDeleted || false,
  }
  handleSave = () => {
    const { onSave, data } = this.props
    onSave(data.id, { ...this.state })
  }
  handleCancel = () => {
    this.props.onCancel()
  }
  handleNameChange = (e) => {
    this.setState({
      name: e.target.value,
    })
  }
  render() {
    const { name } = this.state
    return (
      <Table.Row>
        <Table.Cell width={14}>
          <Input
            value={name}
            onChange={this.handleNameChange}
            size="mini"
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

