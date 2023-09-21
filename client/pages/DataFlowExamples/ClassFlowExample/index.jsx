import React, { Component } from 'react'

class ClassFlowExample extends Component {
  constructor() {
    super()
    this.state = {
      legalUnitId: '',
      legalUnitName: '',
      localUnitId: '',
      localUnitName: '',
      showLegalUnit: false,
      showLocalUnit: false,
    }
  }

  setLegalUnit = () => {
    this.setState({
      legalUnitId: 3,
      legalUnitName: 'LegalUnitName',
      showLegalUnit: true,
      showLocalUnit: false,
    })
  }

  setLocalUnit = () => {
    this.setState({
      localUnitId: 5,
      localUnitName: 'LocalUnitName',
      showLocalUnit: true,
      showLegalUnit: false,
    })
  }

  render() {
    return (
      <div>
        <h1>Class flow example</h1>
        <h3>Stat unit types</h3>
        <div>
          <button onClick={this.setLegalUnit}>Legal unit</button>
          <button onClick={this.setLocalUnit}>Local unit</button>
        </div>
        <br />

        {this.state.showLegalUnit ? (
          <div>
            <strong>Legal unit</strong>
            <div>
              ID:
              <br />
              <input type="text" readOnly value={this.state.legalUnitId} />
              <br />
              Name:
              <br />
              <input type="text" readOnly value={this.state.legalUnitName} />
            </div>
          </div>
        ) : (
          <div />
        )}
        {this.state.showLocalUnit ? (
          <div>
            <strong>Local unit:</strong>
            <div>
              ID:
              <br />
              <input type="text" readOnly value={this.state.localUnitId} />
              <br />
              Name:
              <br />
              <input type="text" readOnly value={this.state.localUnitName} />
              <br />
              Legal unit ID:
              <br />
              <input type="text" readOnly value={this.state.legalUnitId} />
            </div>
          </div>
        ) : (
          <div />
        )}
      </div>
    )
  }
}

export default ClassFlowExample
