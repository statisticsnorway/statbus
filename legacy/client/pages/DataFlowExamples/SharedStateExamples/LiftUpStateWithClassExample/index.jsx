import React, { Component } from 'react'

class LiftUpStateWithClassExample extends Component {
  constructor(props) {
    super(props)
    this.state = {
      legalUnitId: 3,
      showLegalUnit: false,
      showLocalUnit: false,
    }
  }

  setLegalUnit = () => {
    this.setState({
      showLegalUnit: true,
      showLocalUnit: false,
    })
  }

  setLocalUnit = () => {
    this.setState({
      showLocalUnit: true,
      showLegalUnit: false,
    })
  }

  setLegalUnitId = (event) => {
    this.setState({
      legalUnitId: event.target.value,
    })
  }

  render() {
    return (
      <div>
        <h1>Lift up state with class flow example</h1>
        <h3>Stat unit types</h3>
        <div>
          <button onClick={this.setLegalUnit}>Legal unit</button>
          <button onClick={this.setLocalUnit}>Local unit</button>
        </div>
        <br />
        <LegalUnit
          showLegalUnit={this.state.showLegalUnit}
          legalUnitId={this.state.legalUnitId}
          setLegalUnitId={this.setLegalUnitId}
        />
        <LocalUnit
          showLocalUnit={this.state.showLocalUnit}
          legalUnitId={this.state.legalUnitId}
          setLegalUnitId={this.setLegalUnitId}
        />
      </div>
    )
  }
}

class LegalUnit extends Component {
  constructor(props) {
    super(props)
    this.state = {
      legalUnitName: 'LegalUnitName',
    }
  }
  render() {
    return (
      <div>
        {this.props.showLegalUnit ? (
          <div>
            <strong>Legal unit</strong>
            <div>
              ID:
              <br />
              <input
                type="text"
                value={this.props.legalUnitId}
                onChange={this.props.setLegalUnitId}
              />
              <br />
              Name:
              <br />
              <input type="text" value={this.state.legalUnitName} readOnly />
            </div>
          </div>
        ) : (
          <div />
        )}
      </div>
    )
  }
}

class LocalUnit extends Component {
  constructor(props) {
    super(props)
    this.state = {
      localUnitId: '5',
      localUnitName: 'LocalUnitName',
    }
  }
  render() {
    return (
      <div>
        {this.props.showLocalUnit ? (
          <div>
            <strong>Local unit:</strong>
            <div>
              ID:
              <br />
              <input type="text" value={this.state.localUnitId} readOnly />
              <br />
              Name:
              <br />
              <input type="text" value={this.state.localUnitName} readOnly />
              <br />
              Legal unit ID:
              <br />
              <input
                type="text"
                value={this.props.legalUnitId}
                onChange={this.props.setLegalUnitId}
              />
            </div>
          </div>
        ) : (
          <div />
        )}
      </div>
    )
  }
}

export default LiftUpStateWithClassExample
