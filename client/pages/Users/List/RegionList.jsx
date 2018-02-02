import React from 'react'
import { shape, func } from 'prop-types'
import { Button, Confirm } from 'semantic-ui-react'

class RegionList extends React.Component {
  static propTypes = {
    rowData: shape().isRequired,
    localize: func.isRequired,
  }

  state = {
    showFull: false,
  }

  showConfirm = () => {
    this.setState({ showFull: true })
  }

  handleCancel = () => {
    this.setState({ showFull: false })
  }

  render() {
    const { rowData: { regions }, localize } = this.props
    return (
      <div>
        {regions.slice(0, 5).join(', ')}
        {regions.length > 5 && (
          <Button size="mini" onClick={this.showConfirm}>
            ...
          </Button>
        )}
        <Confirm
          open={this.state.showFull}
          onCancel={this.handleCancel}
          onConfirm={this.handleCancel}
          content={regions.join(', ')}
          header={localize('Regions')}
        />
      </div>
    )
  }
}

export default RegionList
